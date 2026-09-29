package dtn.reticulum.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.reticulum.helpers

default decision := {
    "action": "RETAIN",
    "reason": "Bundle valid and stored awaiting routing opportunity",
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

# 3. Alerte de route manquante ou expirée : déclenchement d'une découverte réactive (Path Request)
decision := {
    "action": "RETAIN_AND_REQUEST_PATH",
    "reason": "Bundle destination route unknown or expired: trigger Reticulum path discovery",
    "mutations": [{
        "operation": "TRIGGER_PATH_REQUEST",
        "destination_hash": input.bundle.primary.destination
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_announce(input.bundle)
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.node, "enable_path_requests", false) == true
}

is_valid_route(route, current_time) if {
    route != null
    helpers.is_route_valid(route, current_time)
}
