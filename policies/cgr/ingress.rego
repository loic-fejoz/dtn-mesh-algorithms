package dtn.cgr.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.cgr.constants
import data.dtn.cgr.helpers

default decision := {
    "action": "DROP",
    "reason": "Default CGR ingress rule",
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

# 6. Ingestion d'une mise à jour de Contact Plan CGR
decision := {
    "action": "ACCEPT_CONTACT_PLAN_UPDATE",
    "reason": "CGR Contact Plan update accepted: rebuilding time-expanded contact graph",
    "mutations": [{
        "operation": "UPDATE_CONTACT_PLAN",
        "contacts": contacts
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    helpers.is_cgr_control(input.bundle)
    ingress_obj := object.get(input, "ingress", {})
    contacts := object.get(ingress_obj, "contact_plan", object.get(input.bundle, "contact_plan", null))
    contacts != null
}

# 7. Bundle de données régulier : Acceptation et incrément de saut
decision := {
    "action": "ACCEPT_FORWARD",
    "reason": "Data bundle accepted for CGR scheduled forwarding",
    "mutations": [{
        "block_type": base_constants.block_type_hop_count,
        "operation": "SET_FIELD",
        "field": "hop_count",
        "value": hcb.hop_count + 1
    }]
} if {
    not helpers.is_source_blacklisted(input.bundle.primary.source, input.node)
    not helpers.is_local_destination(input.bundle.primary.destination, input.node)
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.node, "seen_cache", [])
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    not helpers.is_cgr_control(input.bundle)
    hcb := base_helpers.get_hop_count_block(input.bundle)
}
