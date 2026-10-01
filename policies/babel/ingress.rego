package dtn.babel.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.babel.constants
import data.dtn.babel.helpers

default decision := {
    "action": "DROP",
    "reason": "Default Babel/AREDN ingress rule",
    "mutations": []
}

# 1. Rejet silencieux si la source est blacklistée
decision := {
    "action": "DROP",
    "reason": "Source EID is blacklisted on this node",
    "generate_status_report": false,
    "mutations": []
} if {
    helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
}

# 2. Livraison locale si la destination correspond au nœud local
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination matches local node EID",
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    helpers.is_local_destination(input.bundle.primary.destination, input.node)
}

# 3. Rejet des doublons
decision := {
    "action": "DROP",
    "reason": "Duplicate bundle detected in seen cache",
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    canonical_id in object.get(input.node, "seen_cache", [])
}

# 4. Expiration de la durée de vie
decision := {
    "action": "DROP",
    "reason": "Bundle lifetime expired",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 5. Dépassement de la limite de sauts (Hop Count Block Type 10)
decision := {
    "action": "DROP",
    "reason": "Hop limit exceeded (Hop Count Block Type 10)",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    base_helpers.will_exceed_hop_limit(input.bundle)
}

# 6. Ingestion d'un message UPDATE Babel : Amélioration de route ou nouveau seqno
decision := {
    "action": "ACCEPT_BABEL_UPDATE",
    "reason": sprintf("Babel update accepted: route to %v via %v updated (metric: %v, seqno: %v)", [
        prefix,
        peer_eid,
        total_metric,
        update_seqno
    ]),
    "mutations": [
        {
            "operation": "UPDATE_ROUTING_TABLE",
            "prefix_eid": prefix,
            "next_hop": peer_eid,
            "metric": total_metric,
            "seqno": update_seqno,
            "feasible_distance": total_metric,
            "expires_at_ms": input.current_dtn_time_ms + constants.default_route_expiry_ms
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hcb.hop_count + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_babel_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    
    update := object.get(input.ingress, "babel_update", object.get(input.bundle, "babel_update", {}))
    prefix := update.prefix_eid
    adv_metric := update.metric
    update_seqno := update.seqno
    peer_eid := object.get(input.ingress, "peer_eid", input.bundle.primary.source)
    link_cost := object.get(input.ingress, "link_cost", 10)
    total_metric := min([adv_metric + link_cost, constants.metric_infinity])
    
    existing := helpers.get_route_entry(prefix, object.get(input.node, "routing_table", {}))
    helpers.should_update_babel_route(existing, update_seqno, total_metric, input.current_dtn_time_ms)
}

# 7. Message UPDATE Babel reçu mais sans modification (route moins bonne ou non faisable)
decision := {
    "action": "ACCEPT_BABEL_UPDATE_NO_CHANGE",
    "reason": "Babel update ignored: existing route is better or update fails feasibility condition",
    "mutations": [{
        "block_type": base_constants.block_type_hop_count,
        "operation": "SET_FIELD",
        "field": "hop_count",
        "value": hcb.hop_count + 1
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_babel_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    
    update := object.get(input.ingress, "babel_update", object.get(input.bundle, "babel_update", {}))
    prefix := update.prefix_eid
    adv_metric := update.metric
    update_seqno := update.seqno
    link_cost := object.get(input.ingress, "link_cost", 10)
    total_metric := min([adv_metric + link_cost, constants.metric_infinity])
    
    existing := helpers.get_route_entry(prefix, object.get(input.node, "routing_table", {}))
    not helpers.should_update_babel_route(existing, update_seqno, total_metric, input.current_dtn_time_ms)
}

# 8. Bundle de données normal : Acceptation et incrément de saut
decision := {
    "action": "ACCEPT_FORWARD",
    "reason": "Data bundle accepted for Babel/AREDN next-hop forwarding",
    "mutations": [{
        "block_type": base_constants.block_type_hop_count,
        "operation": "SET_FIELD",
        "field": "hop_count",
        "value": hcb.hop_count + 1
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    not helpers.is_babel_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
}
