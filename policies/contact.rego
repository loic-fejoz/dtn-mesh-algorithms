package dtn.contact

import future.keywords.if
import future.keywords.in

import data.dtn.constants
import data.dtn.helpers

# Décision par défaut : ne pas transmettre à ce contact
default decision := {
    "action": "SKIP",
    "reason": "No forwarding rule matched",
    "generate_status_report": false,
    "mutations": []
}

# 1. Le bundle a expiré avant émission
decision := {
    "action": "DROP",
    "reason_code": constants.reason_lifetime_expired,
    "reason": "Bundle expired in store before forwarding opportunity",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 2. Le hop count a atteint la limite avant émission (RFC 9171 Section 4.3.3 :
# "Before a bundle that contains a hop count block is forwarded, if the hop count
# of the block is equal to the hop limit of the block, the bundle MUST be deleted;
# it MUST NOT be forwarded.")
decision := {
    "action": "DROP",
    "reason_code": constants.reason_hop_limit_exceeded,
    "reason": "Hop limit already reached prior to forward",
    "generate_status_report": helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    helpers.is_hop_limit_reached(input.bundle)
}

# 3. Évitement de boucle immédiate (Split Horizon) : ne pas renvoyer au nœud précédent (Type 6)
decision := {
    "action": "SKIP",
    "reason": "Peer is the previous sender (split-horizon / loop avoidance)",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_hop_limit_reached(input.bundle)
    pib := helpers.get_extension_block(input.bundle.extension_blocks, constants.block_type_previous_node)
    pib.previous_node == input.contact.peer_eid
}

# 4. Transmission directe à la destination finale
decision := {
    "action": "FORWARD",
    "reason": "Peer is the final destination",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_hop_limit_reached(input.bundle)
    not is_previous_node(input.bundle, input.contact.peer_eid)
    input.bundle.primary.destination == input.contact.peer_eid
}

# 5. Transmission opportuniste vers un relais intermédiaire
decision := {
    "action": "FORWARD",
    "reason": "Peer is an eligible relay for opportunistic forwarding",
    "generate_status_report": false,
    "mutations": []
} if {
    not helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not helpers.is_hop_limit_reached(input.bundle)
    not is_previous_node(input.bundle, input.contact.peer_eid)
    input.bundle.primary.destination != input.contact.peer_eid
}

# Helper local pour tester si le pair est le nœud amont immédiat
is_previous_node(bundle, peer_eid) if {
    pib := helpers.get_extension_block(bundle.extension_blocks, constants.block_type_previous_node)
    pib.previous_node == peer_eid
}
