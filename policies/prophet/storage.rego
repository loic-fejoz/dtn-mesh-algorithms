package dtn.prophet.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants as dtn_constants
import data.dtn.helpers as dtn_helpers
import data.dtn.prophet.helpers as prophet_helpers

default decision := {
    "action": "RETAIN",
    "reason": "Bundle within lifetime and storage limits",
    "mutations": []
}

# 1. Destruction périodique si la durée de vie a expiré
decision := {
    "action": "DROP",
    "reason": "Lifetime expired during storage audit",
    "mutations": []
} if {
    dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 2. Mise à jour de l'âge relatif pour les bundles sans horloge synchronisée
decision := {
    "action": "RETAIN_AND_UPDATE_AGE",
    "reason": "Update Bundle Age Block for untimed bundle",
    "mutations": [{
        "block_type": dtn_constants.block_type_bundle_age,
        "operation": "INCREMENT_BUNDLE_AGE",
        "added_ms": input.elapsed_since_last_audit_ms
    }]
} if {
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    input.bundle.primary.creation_timestamp.time == 0
    input.elapsed_since_last_audit_ms > 0
}

# 3. Éviction en cas de débordement mémoire (Buffer Overflow Eviction)
# Selon la RFC 6693, un nœud en saturation mémoire évince en priorité les bundles
# dont la destination a la plus faible probabilité de rencontre P(local, dest).
decision := {
    "action": "EVICT_LOW_PREDICTABILITY",
    "reason": sprintf("Storage full: evicted bundle due to low delivery predictability P(local, dest)=%v", [p_local]),
    "mutations": [],
    "eviction_metric": p_local
} if {
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    used := object.get(input.node, "storage_used_bytes", 0)
    capacity := object.get(input.node, "storage_capacity_bytes", 0)
    capacity > 0
    used > capacity
    p_local := prophet_helpers.get_local_predictability(input.node, input.bundle.primary.destination)
    eviction_threshold := object.get(input.node, "eviction_predictability_threshold", 0.1)
    p_local <= eviction_threshold
}
