package dtn.reticulum.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.reticulum.constants
import data.dtn.reticulum.helpers

default decision := {
    "action": "DROP",
    "reason": "Default Reticulum ingress rule",
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

# 2. Livraison locale si la destination correspond au nœud local ou à son hash cryptographique
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination matches local node or cryptographic destination hash",
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

# 5. Dépassement de la limite de saut (Hop Count Block Type 10)
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

# 6. Annonce Reticulum (Announce) : découverte de chemin et mise à jour de la table de routage
decision := {
    "action": "ACCEPT_ANNOUNCE",
    "reason": sprintf("Reticulum announce accepted: discovered next-hop path to %v via %v (%v hops)", [
        announced_dest,
        peer_eid,
        hops + 1
    ]),
    "mutations": [
        {
            "operation": "UPDATE_ROUTING_TABLE",
            "destination_hash": announced_dest,
            "next_hop": peer_eid,
            "hops": hops + 1,
            "expires_at_ms": input.current_dtn_time_ms + constants.default_path_ttl_ms
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hops + 1
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_announce(input.bundle)
    announced_dest := input.bundle.primary.source
    peer_eid := object.get(input.ingress, "peer_eid", announced_dest)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    hops := hcb.hop_count
    existing := helpers.get_route_entry(announced_dest, object.get(input.node, "routing_table", {}))
    helpers.should_update_path(existing, hops + 1, input.current_dtn_time_ms)
}

# 7. Annonce Reticulum : Acceptée mais sans mise à jour de table (chemin existant meilleur ou égal)
decision := {
    "action": "ACCEPT_ANNOUNCE_NO_UPDATE",
    "reason": "Reticulum announce accepted but existing routing path is equal or shorter",
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
    helpers.is_announce(input.bundle)
    announced_dest := input.bundle.primary.source
    hcb := base_helpers.get_hop_count_block(input.bundle)
    existing := helpers.get_route_entry(announced_dest, object.get(input.node, "routing_table", {}))
    not helpers.should_update_path(existing, hcb.hop_count + 1, input.current_dtn_time_ms)
}

# 8. Bundle de données normal : Acceptation et incrément de saut
decision := {
    "action": "ACCEPT_FORWARD",
    "reason": "Data bundle accepted for Reticulum next-hop forwarding",
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
    not helpers.is_announce(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
}
