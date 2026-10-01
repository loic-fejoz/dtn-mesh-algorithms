package dtn.geodtn.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers

default decision := {
    "action": "RETAIN",
    "reason": "Bundle valid and carried in storage (Greedy-Carry-and-Forward)",
    "mutations": []
}

# 1. Destruction périodique si la durée de vie a expiré
decision := {
    "action": "DROP",
    "reason": "Lifetime expired during storage audit",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 2. Mise à jour de l'âge relatif pour les bundles sans horloge synchronisée
decision := {
    "action": "RETAIN_AND_UPDATE_AGE",
    "reason": "Update Bundle Age Block for untimed bundle",
    "mutations": [{
        "block_type": base_constants.block_type_bundle_age,
        "operation": "INCREMENT_BUNDLE_AGE",
        "added_ms": input.elapsed_since_last_audit_ms
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    input.bundle.primary.creation_timestamp.time == 0
    input.elapsed_since_last_audit_ms > 0
}
