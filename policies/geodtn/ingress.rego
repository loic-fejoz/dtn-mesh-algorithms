package dtn.geodtn.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.geodtn.constants
import data.dtn.geodtn.helpers

default decision := {
    "action": "DROP",
    "reason": "Default GeoDTN ingress rule",
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

# 2. Livraison locale si destination EID exacte ou si le nœud est situé dans la zone Geocast
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Local delivery: node matches EID or is inside targeted Geocast spatial scope",
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    helpers.is_local_destination(input.bundle, input.node)
}

# 3. Rejet des doublons
decision := {
    "action": "DROP",
    "reason": "Duplicate bundle detected in seen cache",
    "mutations": []
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle, input.node)
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
    not helpers.is_local_destination(input.bundle, input.node)
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
    not helpers.is_local_destination(input.bundle, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    base_helpers.will_exceed_hop_limit(input.bundle)
}

# 6. Bundle admis pour acheminement géographique
decision := {
    "action": "ACCEPT_FORWARD",
    "reason": "Bundle accepted for geographic forwarding",
    "mutations": [{
        "block_type": base_constants.block_type_hop_count,
        "operation": "SET_FIELD",
        "field": "hop_count",
        "value": hcb.hop_count + 1
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle, input.node)
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.node, "seen_cache", [])
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
}
