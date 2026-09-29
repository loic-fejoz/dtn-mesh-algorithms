package dtn.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants
import data.dtn.helpers

# Décision par défaut : conserver le bundle
default decision := {
    "action": "RETAIN",
    "reason": "Bundle still valid",
    "generate_status_report": false,
    "mutations": []
}

# 1. Expiration de la Lifetime pendant le stockage
decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle lifetime expired during storage retention",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 2. Rétention avec mise à jour du Bundle Age Block (Type 7) pour les nœuds sans horloge synchronisée
decision := {
    "action": "RETAIN",
    "reason": "Bundle retained, age updated",
    "generate_status_report": false,
    "mutations": [
        {
            "block_type": constants.block_type_bundle_age,
            "operation": "INCREMENT_FIELD",
            "field": "bundle_age_ms",
            "value": input.elapsed_since_last_audit_ms
        }
    ]
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    age_block := helpers.get_extension_block(input.bundle.extension_blocks, constants.block_type_bundle_age)
    input.elapsed_since_last_audit_ms > 0
}
