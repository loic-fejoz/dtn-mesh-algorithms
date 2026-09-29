package dtn.maxprop.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.maxprop.constants
import data.dtn.maxprop.helpers

default decision := {
    "action": "DROP",
    "reason": "Default MaxProp ingress rule",
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

# 4. Rejet immédiat si le bundle figure déjà dans la Cleared List (déjà livré à destination)
decision := {
    "action": "DROP",
    "reason": "Bundle already acknowledged in Cleared List",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
}

# 5. Expiration de la durée de vie
decision := {
    "action": "DROP",
    "reason": "Bundle lifetime expired",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 6. Dépassement de la limite de sauts (Hop Count Block Type 10)
decision := {
    "action": "DROP",
    "reason": "Hop limit exceeded (Hop Count Block Type 10)",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    base_helpers.will_exceed_hop_limit(input.bundle)
}

# 7. Ingestion d'un message Cleared List MaxProp
decision := {
    "action": "ACCEPT_CLEARED_LIST",
    "reason": "MaxProp Cleared List ingested: updating delivered bundles inventory",
    "mutations": [
        {
            "operation": "UPDATE_CLEARED_LIST",
            "cleared_bundle_ids": cleared_ids
        },
        {
            "operation": "PURGE_DELIVERED_BUNDLES",
            "cleared_bundle_ids": cleared_ids
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_maxprop_control(input.bundle)
    ingress_obj := object.get(input, "ingress", {})
    cleared_ids := object.get(ingress_obj, "cleared_list", object.get(input.bundle, "cleared_list", null))
    cleared_ids != null
}

# 8. Ingestion d'un vecteur de probabilités MaxProp (Gossip à 2 sauts)
decision := {
    "action": "ACCEPT_PROB_VECTOR",
    "reason": "MaxProp contact probability vector ingested: updating local encounter graph",
    "mutations": [{
        "operation": "UPDATE_CONTACT_PROBABILITIES",
        "peer_eid": input.bundle.primary.source,
        "probabilities": probs
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_maxprop_control(input.bundle)
    ingress_obj := object.get(input, "ingress", {})
    cleared_ids := object.get(ingress_obj, "cleared_list", object.get(input.bundle, "cleared_list", null))
    cleared_ids == null
    probs := object.get(ingress_obj, "contact_probabilities", object.get(input.bundle, "contact_probabilities", null))
    probs != null
}

# 9. Bundle de données normal : Acceptation, incrément de saut et calcul du coût de tri HP-MaxProp
decision := {
    "action": "ACCEPT_FORWARD",
    "reason": sprintf("Data bundle accepted: HP-MaxProp sorting cost computed (%v)", [sorting_cost]),
    "mutations": [
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hcb.hop_count + 1
        },
        {
            "operation": "SET_SORTING_COST",
            "sorting_cost": sorting_cost
        }
    ]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.node, "seen_cache", [])
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    not helpers.is_maxprop_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
    dijkstra_cost := object.get(input.bundle, "dijkstra_cost", 1.0)
    sorting_cost := helpers.compute_sorting_cost(dijkstra_cost, hcb.hop_count + 1)
}
