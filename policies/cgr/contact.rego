package dtn.cgr.contact

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.cgr.constants
import data.dtn.cgr.helpers

default decision := {
    "action": "SKIP",
    "reason": "Default CGR contact rule",
    "mutations": []
}

# 1. Contact direct avec la destination finale
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer matches final destination endpoint",
    "mutations": []
} if {
    not input.contact.is_broadcast
    input.contact.peer_eid == input.bundle.primary.destination
}

# 2. Expiration de durée de vie avant transmission
decision := {
    "action": "DROP",
    "reason": "Bundle lifetime expired prior to forwarding",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 3. Évitement de boucle immédiate (Split Horizon - Type 6)
decision := {
    "action": "SKIP",
    "reason": "Skip proximate sender node (split horizon)",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
}

# 4. Rediffusion des messages de signalisation CGR en broadcast
decision := {
    "action": "FORWARD_BROADCAST",
    "reason": "CGR control message broadcast to local space nodes",
    "mutations": []
} if {
    input.contact.is_broadcast == true
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    helpers.is_cgr_control(input.bundle)
}

# 5. Acheminement déterministe CGR lors d'une fenêtre de contact active
decision := {
    "action": "FORWARD_CGR_SCHEDULED",
    "reason": sprintf("CGR contact window active with %v (EDT: %v, remaining capacity: %v)", [
        path.next_hop_eid,
        path.earliest_delivery_time_ms,
        path.remaining_capacity_bytes
    ]),
    "mutations": [{
        "operation": "DECREMENT_CONTACT_CAPACITY",
        "contact_id": path.first_contact_id,
        "bytes": bundle_size
    }]
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_cgr_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    path != null
    input.contact.peer_eid == path.next_hop_eid
    helpers.is_path_viable(path, input.bundle, input.current_dtn_time_ms)
    
    contact := object.get(input.contact, "scheduled_contact", null)
    contact != null
    helpers.is_contact_active(contact, input.current_dtn_time_ms)
    
    bundle_size := object.get(input.bundle, "total_size_bytes", 1024)
}

# 6. Ignorer le pair s'il n'est pas le prochain saut désigné pour le chemin CGR
decision := {
    "action": "SKIP",
    "reason": sprintf("Peer %v is not designated next-hop for scheduled CGR path (expected: %v)", [
        input.contact.peer_eid,
        path.next_hop_eid
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_cgr_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    path != null
    input.contact.peer_eid != path.next_hop_eid
}

# 7. Le pair est le prochain saut, mais la fenêtre de contact n'est pas active ou capacité insuffisante
decision := {
    "action": "SKIP",
    "reason": "Scheduled CGR contact window is not currently open or capacity insufficient: retaining bundle",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_cgr_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    path != null
    input.contact.peer_eid == path.next_hop_eid
    is_window_unusable(path, input.contact, input.bundle, input.current_dtn_time_ms)
}

# 8. Aucun chemin CGR planifié vers la destination
decision := {
    "action": "SKIP",
    "reason": "No scheduled CGR contact path found in plan for destination",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_cgr_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    
    path := helpers.get_cgr_path(input.bundle.primary.destination, object.get(input.node, "cgr_routes", {}))
    path == null
}

# Prédicat d'aide : fenêtre fermée ou pas de contact actif ou capacité insuffisante
is_window_unusable(path, contact_obj, _, current_time) if {
    contact := object.get(contact_obj, "scheduled_contact", null)
    not helpers.is_contact_active(contact, current_time)
}

is_window_unusable(path, _, bundle, current_time) if {
    not helpers.is_path_viable(path, bundle, current_time)
}
