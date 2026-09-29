package dtn.reticulum.contact

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.reticulum.constants
import data.dtn.reticulum.helpers

default decision := {
    "action": "SKIP",
    "reason": "Default Reticulum contact rule (no next-hop match)",
    "mutations": []
}

# 1. Contact direct avec la destination finale (adresse EID ou hash cryptographique)
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer matches final destination endpoint",
    "mutations": []
} if {
    not input.contact.is_broadcast
    input.contact.peer_eid == input.bundle.primary.destination
}

decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer matches destination hash",
    "mutations": []
} if {
    not input.contact.is_broadcast
    input.contact.peer_eid != input.bundle.primary.destination
    peer_hash := object.get(input.contact, "reticulum_destination_hash", null)
    peer_hash != null
    contains(input.bundle.primary.destination, peer_hash)
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

# 4. Rediffusion des Annonces Reticulum (Broadcast / Flooding contrôlé des annonces)
decision := {
    "action": "FORWARD_BROADCAST",
    "reason": "Reticulum announce broadcast to local mesh peers",
    "mutations": []
} if {
    input.contact.is_broadcast == true
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    helpers.is_announce(input.bundle)
}

# 5. Acheminement vers le Prochain Saut (Next-Hop Routing Table Match)
decision := {
    "action": "FORWARD_NEXT_HOP",
    "reason": sprintf("Routing table match: forwarding to next-hop %v (%v hops to destination)", [
        route.next_hop_eid,
        route.hops
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_announce(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    route != null
    helpers.is_route_valid(route, input.current_dtn_time_ms)
    input.contact.peer_eid == route.next_hop_eid
}

# 6. Ignorer les pairs qui ne sont pas le prochain saut désigné
decision := {
    "action": "SKIP",
    "reason": sprintf("Contact peer %v is not the designated next-hop for destination (expected: %v)", [
        input.contact.peer_eid,
        route.next_hop_eid
    ]),
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_announce(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    route != null
    helpers.is_route_valid(route, input.current_dtn_time_ms)
    input.contact.peer_eid != route.next_hop_eid
}

# 7. Destination inconnue ou route expirée : Rétention en stockage (Store-Carry-and-Forward)
decision := {
    "action": "SKIP",
    "reason": "No valid next-hop route in table: holding bundle in store awaiting announce or path response",
    "mutations": []
} if {
    not input.contact.is_broadcast
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not helpers.is_announce(input.bundle)
    input.contact.peer_eid != input.bundle.primary.destination
    route := helpers.get_route_entry(input.bundle.primary.destination, object.get(input.node, "routing_table", {}))
    not is_valid_route(route, input.current_dtn_time_ms)
}

is_valid_route(route, current_time) if {
    route != null
    helpers.is_route_valid(route, current_time)
}
