package dtn.aprs.contact

import future.keywords.if
import future.keywords.in

import data.dtn.aprs.constants
import data.dtn.aprs.helpers

default decision := {
    "action": "SKIP",
    "reason": "Default contact rule (no forwarding condition matched)",
    "mutations": []
}

# 1. Émission en diffusion (Broadcast AX.25 / LoRa standard en APRS)
decision := {
    "action": "FORWARD_BROADCAST",
    "reason": "Broadcast digipeated packet onto shared radio channel",
    "mutations": []
} if {
    input.contact.is_broadcast == true
}

# 2. Transmission unicast vers un voisin direct si le prochain saut strict lui correspond
decision := {
    "action": "FORWARD_UNICAST",
    "reason": sprintf("Peer matches the next strict hop (%v)", [input.contact.peer_eid]),
    "mutations": []
} if {
    input.contact.is_broadcast != true
    block := helpers.get_aprs_block(input.bundle)
    hop := helpers.get_active_hop(block.payload)
    hop.hop_kind == constants.hop_kind_strict
    hop.node_identifier == input.contact.peer_eid
}
