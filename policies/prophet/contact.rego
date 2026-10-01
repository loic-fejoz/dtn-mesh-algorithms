package dtn.prophet.contact

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as dtn_helpers
import data.dtn.prophet.constants
import data.dtn.prophet.helpers as prophet_helpers

default decision := {
    "action": "SKIP",
    "reason": "Default PRoPHET rule: peer does not offer routing advantage",
    "mutations": []
}

# 1. Contact direct avec la destination finale : transmission prioritaire
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Contact peer is the destination endpoint",
    "mutations": []
} if {
    input.contact.peer_eid == input.bundle.primary.destination
}

# 2. Rejet si la durée de vie est expirée au moment du contact
decision := {
    "action": "DROP",
    "reason": "Bundle lifetime expired prior to forwarding",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 3. Évitement de boucle immédiate (Split Horizon / Previous Node Block Type 6)
decision := {
    "action": "SKIP",
    "reason": "Skip proximate sender node (split horizon)",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    dtn_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
}

# 4. Déduplication par Summary Vector : le pair possède déjà le bundle
decision := {
    "action": "SKIP",
    "reason": "Peer already holds this bundle in summary vector",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not dtn_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    prophet_helpers.peer_already_holds_bundle(input.contact, input.bundle)
}

# 5. Seuil d'utilité opportuniste non satisfait par le pair
decision := {
    "action": "SKIP",
    "reason": sprintf("Peer predictability P(peer, dest)=%v does not meet bundle threshold %v", [p_peer, threshold]),
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not dtn_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not prophet_helpers.peer_already_holds_bundle(input.contact, input.bundle)
    threshold := prophet_helpers.get_opportunistic_threshold(input.bundle)
    threshold != null
    p_peer := prophet_helpers.get_peer_predictability(input.contact, input.bundle.primary.destination)
    p_peer < threshold
}

# 6. Relais opportuniste favorable selon PRoPHET : P(peer, dest) > P(local, dest)
decision := {
    "action": "FORWARD_OPPORTUNISTIC",
    "reason": sprintf("Peer has higher delivery predictability P(peer, dest)=%v than local P(local, dest)=%v", [p_peer, p_local]),
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not dtn_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not prophet_helpers.peer_already_holds_bundle(input.contact, input.bundle)
    threshold := prophet_helpers.get_opportunistic_threshold(input.bundle)
    p_local := prophet_helpers.get_local_predictability(input.node, input.bundle.primary.destination)
    p_peer := prophet_helpers.get_peer_predictability(input.contact, input.bundle.primary.destination)
    prophet_helpers.satisfies_threshold(p_peer, threshold)
    prophet_helpers.is_forwarding_favorable(p_peer, p_local, constants.default_forward_margin)
}

# 7. Refus de transmission si le pair n'offre aucun avantage probabiliste
decision := {
    "action": "SKIP",
    "reason": sprintf("Local node predictability P(local, dest)=%v is greater than or equal to peer P(peer, dest)=%v", [p_local, p_peer]),
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    not dtn_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not dtn_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    not prophet_helpers.peer_already_holds_bundle(input.contact, input.bundle)
    threshold := prophet_helpers.get_opportunistic_threshold(input.bundle)
    p_local := prophet_helpers.get_local_predictability(input.node, input.bundle.primary.destination)
    p_peer := prophet_helpers.get_peer_predictability(input.contact, input.bundle.primary.destination)
    prophet_helpers.satisfies_threshold(p_peer, threshold)
    not prophet_helpers.is_forwarding_favorable(p_peer, p_local, constants.default_forward_margin)
}
