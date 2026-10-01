package dtn.babel.storage

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.babel.helpers

default decision := {
    "action": "RETAIN",
    "reason": "Bundle valid and retained in storage buffer",
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

# 3. Déclenchement d'une demande de route Babel si la destination est inconnue ou expirée
decision := {
    "action": "RETAIN_AND_REQUEST_ROUTE",
    "reason": "Destination route unknown or unfeasible: trigger Babel route request",
    "mutations": [{
        "operation": "TRIGGER_BABEL_ROUTE_REQUEST",
        "prefix_eid": input.bundle.primary.destination
    }]
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_babel_control(input.bundle)
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.node, "enable_babel_requests", false) == true
}

is_valid_route(route, current_time) if {
    route != null
    helpers.is_route_valid(route, current_time)
}
