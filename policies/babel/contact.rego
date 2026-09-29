package dtn.babel.contact

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.babel.constants
import data.dtn.babel.helpers

default decision := {
    "action": "SKIP",
    "reason": "Default Babel/AREDN contact rule",
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

# 4. Diffusion des messages de contrôle Babel sur interface broadcast
decision := {
    "action": "FORWARD_BROADCAST",
    "reason": "Babel control message broadcast to local mesh peers",
    "mutations": []
} if {
    input.contact.is_broadcast == true
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    helpers.is_babel_control(input.bundle)
}

# 5. Acheminement Next-Hop proactif au sein de l'îlot maillé AREDN
decision := {
    "action": "FORWARD_NEXT_HOP",
    "reason": sprintf("Babel routing table match: forwarding to next-hop %v (metric: %v)", [
        route.next_hop_eid,
        route.metric
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_babel_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    route != null
    helpers.is_route_valid(route, input.current_dtn_time_ms)
    input.contact.peer_eid == route.next_hop_eid
}

# 6. Ignorer le pair s'il n'est pas le prochain saut désigné pour une route connue
decision := {
    "action": "SKIP",
    "reason": sprintf("Peer %v is not designated next-hop for destination (designated: %v)", [
        input.contact.peer_eid,
        route.next_hop_eid
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_babel_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    route != null
    helpers.is_route_valid(route, input.current_dtn_time_ms)
    input.contact.peer_eid != route.next_hop_eid
}

# 7. Hybridation HYMAD : Destination hors de portée de l'îlot maillé AREDN,
#    mais contact avec un vecteur/ferry DTN inter-îlots (Store-Carry-and-Forward)
decision := {
    "action": "FORWARD_DTN_CARRIER",
    "reason": "Destination unreachable via local AREDN mesh: offloading to opportunistic DTN inter-cluster carrier",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_babel_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.contact, "is_dtn_carrier", false) == true
}

# 8. Destination sans route active et pair ordinaire : rétention en mémoire tampon
decision := {
    "action": "SKIP",
    "reason": "No active route in local AREDN mesh and peer is not an inter-cluster DTN carrier: holding bundle",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_babel_control(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
    object.get(input.contact, "is_dtn_carrier", false) != true
}

is_valid_route(route, current_time) if {
    route != null
    helpers.is_route_valid(route, current_time)
}
