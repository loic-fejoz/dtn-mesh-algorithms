package dtn.maxprop.contact

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.maxprop.constants
import data.dtn.maxprop.helpers

default decision := {
    "action": "SKIP",
    "reason": "Default MaxProp contact rule",
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

# 4. Rediffusion des messages de contrôle MaxProp en broadcast
decision := {
    "action": "FORWARD_BROADCAST",
    "reason": "MaxProp control message broadcast to local mesh peers",
    "mutations": []
} if {
    input.contact.is_broadcast == true
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    helpers.is_maxprop_control(input.bundle)
}

# 5. Ne pas transmettre un bundle déjà présent dans la Cleared List
decision := {
    "action": "SKIP_CLEARED",
    "reason": "Bundle already delivered and present in Cleared List",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_maxprop_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
}

# 6. Sauter si le pair détient déjà ce bundle (Summary Vector)
decision := {
    "action": "SKIP",
    "reason": "Peer already holds this bundle in buffer",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_maxprop_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    canonical_id in object.get(input.contact, "held_bundle_ids", [])
}

# 7. Relais opportuniste favorable : Le pair a un coût de chemin Dijkstra inférieur vers la destination
decision := {
    "action": "FORWARD_FAVORABLE",
    "reason": sprintf("Peer %v has lower Dijkstra path cost to %v (%v < %v)", [
        input.contact.peer_eid,
        input.bundle.primary.destination,
        peer_cost,
        my_cost
    ]),
    "mutations": [{
        "operation": "SET_PRIORITY_COST",
        "sorting_cost": sorting_cost
    }]
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_maxprop_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.contact, "held_bundle_ids", [])
    
    dest := input.bundle.primary.destination
    my_cost := helpers.get_path_cost(dest, object.get(input.node, "path_costs", {}))
    peer_cost := helpers.get_path_cost(dest, object.get(input.contact, "peer_path_costs", {}))
    peer_cost < my_cost
    
    hcb := base_helpers.get_hop_count_block(input.bundle)
    sorting_cost := helpers.compute_sorting_cost(my_cost, hcb.hop_count)
}

# 8. Relais défavorable : Le pair n'a pas un meilleur coût vers la destination
decision := {
    "action": "SKIP",
    "reason": sprintf("Peer %v does not offer better path cost to %v (%v >= %v)", [
        input.contact.peer_eid,
        input.bundle.primary.destination,
        peer_cost,
        my_cost
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_maxprop_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    not helpers.is_bundle_cleared(input.bundle, object.get(input.node, "cleared_list", []))
    canonical_id := base_helpers.get_bundle_id(input.bundle)
    not canonical_id in object.get(input.contact, "held_bundle_ids", [])
    
    dest := input.bundle.primary.destination
    my_cost := helpers.get_path_cost(dest, object.get(input.node, "path_costs", {}))
    peer_cost := helpers.get_path_cost(dest, object.get(input.contact, "peer_path_costs", {}))
    peer_cost >= my_cost
}
