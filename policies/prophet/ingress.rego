package dtn.prophet.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as dtn_constants
import data.dtn.helpers as dtn_helpers
import data.dtn.prophet.helpers as prophet_helpers

default decision := {
    "action": "ACCEPT",
    "reason": "Bundle accepted for PRoPHET routing and store-and-forward",
    "mutations": []
}

# 1. Délivrance locale prioritaire
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Bundle reached final destination endpoint",
    "mutations": []
} if {
    input.bundle.primary.destination == input.node.local_eid
}

# 2. Rejet des doublons
decision := {
    "action": "DROP",
    "reason": "Duplicate bundle detected in seen cache",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    prophet_helpers.is_bundle_seen(input.bundle, object.get(input.node, "seen_cache", []))
}

# 3. Rejet pour expiration de durée de vie
decision := {
    "action": "DROP",
    "reason": "Bundle lifetime expired",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 4. Rejet pour dépassement du nombre maximal de sauts (Hop Count Block Type 10)
decision := {
    "action": "DROP",
    "reason": "Hop count limit reached",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    dtn_helpers.will_exceed_hop_limit(input.bundle)
}

# 5. Acceptation avec incrémentation standard du Hop Count Block
decision := {
    "action": "ACCEPT",
    "reason": "Bundle accepted and hop count incremented",
    "mutations": [{
        "block_type": dtn_constants.block_type_hop_count,
        "operation": "INCREMENT_HOP_COUNT",
        "new_hop_count": hcb.hop_count + 1
    }]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not prophet_helpers.is_bundle_seen(input.bundle, object.get(input.node, "seen_cache", []))
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not dtn_helpers.will_exceed_hop_limit(input.bundle)
    hcb := dtn_helpers.get_hop_count_block(input.bundle)
}
