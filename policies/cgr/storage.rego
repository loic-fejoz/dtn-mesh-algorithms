package dtn.cgr.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.cgr.helpers

default decision := {
    "action": "RETAIN",
    "reason": "Bundle valid and retained awaiting scheduled CGR contact window",
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

# 3. Abandon préventif déterministe (Infeasible Schedule) :
# En CGR, si l'audit mathématique démontre qu'aucun calendrier de contact ne peut
# livrer le bundle avant son expiration (EDT > Lifetime), le paquet est abandonné
# immédiatement pour ne pas encombrer les mémoires de bord des sondes spatiales.
decision := {
    "action": "DROP_INFEASIBLE_SCHEDULE",
    "reason": "Deterministic CGR check: Earliest Delivery Time exceeds bundle lifetime",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_cgr_control(input.bundle)
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    is_path_impossible(path, input.bundle)
}

is_path_impossible(path, bundle) if {
    path != null
    creation_time := bundle.primary.creation_timestamp.time
    lifetime := bundle.primary.lifetime
    path.earliest_delivery_time_ms > (creation_time + lifetime)
}

is_path_impossible(null, _) if false
