package dtn.maxprop.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.maxprop.helpers

default decision := {
    "action": "RETAIN",
    "reason": "Bundle valid and retained in MaxProp priority queue",
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

# 2. Purge immédiate si le bundle figure dans la Cleared List
decision := {
    "action": "PURGE_CLEARED",
    "reason": "Bundle confirmed delivered in Cleared List: purged from local store",
    "generate_status_report": false,
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
}

# 3. Mise à jour de l'âge relatif pour les bundles sans horloge synchronisée
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
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    input.bundle.primary.creation_timestamp.time == 0
    input.elapsed_since_last_audit_ms > 0
}

# 4. Éviction sélective en cas de saturation mémoire (Buffer Overflow) :
# Les paquets ayant le coût de tri le plus élevé (pire chemin + pénalité de saut)
# sont évincés en premier lorsque le buffer est plein.
decision := {
    "action": "EVICT_LOW_PRIORITY",
    "reason": sprintf("Buffer congestion: evicting bundle with high sorting cost (%v >= threshold %v)", [
        sorting_cost,
        threshold
    ]),
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    object.get(input.node, "buffer_full", false) == true
    threshold := object.get(input.node, "eviction_cost_threshold", 5.0)
    
    hcb := base_helpers.get_hop_count_block(input.bundle)
    dijkstra_cost := object.get(input.bundle, "dijkstra_cost", 1.0)
    sorting_cost := helpers.compute_sorting_cost(dijkstra_cost, hcb.hop_count)
    sorting_cost >= threshold
}
