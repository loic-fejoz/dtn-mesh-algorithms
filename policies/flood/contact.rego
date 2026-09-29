package dtn.flood.contact

import future.keywords.if
import future.keywords.in

import data.dtn.flood.constants
import data.dtn.flood.helpers

# Décision par défaut : SKIP
default decision := {
    "action": "SKIP",
    "reason": "Default contact rule (no forwarding condition matched)",
    "mutations": []
}

# 1. Contact direct avec la destination finale (Valide pour tous les protocoles)
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer is the destination endpoint",
    "mutations": []
} if {
    not input.contact.is_broadcast
    input.contact.peer_eid == input.bundle.primary.destination
}

# 2. Réplication / Spray and Wait : Le pair possède déjà une copie du bundle
decision := {
    "action": "SKIP",
    "reason": "Peer already holds a copy of this bundle (summary vector check)",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    helpers.peer_already_holds_entire_bundle(input.contact, input.bundle)
}

# 3. Réplication / Spray and Wait : Phase WAIT (Quota L == 1)
# En phase Wait, la transmission à un relais intermédiaire est formellement interdite.
decision := {
    "action": "SKIP",
    "reason": "Spray & Wait bundle is in WAIT phase (L=1): awaiting direct destination contact only",
    "mutations": []
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_entire_bundle(input.contact, input.bundle)
    helpers.get_quota(block) <= 1
}

# 4. Réplication / Spray and Wait : Phase SPRAY en mode BINAIRE (L >= 2)
# Division par deux des copies : floor(L/2) transmises, le reste conservé localement
decision := {
    "action": "FORWARD_REPLICATE",
    "reason": sprintf("Binary spray: splitting quota L=%v -> sending %v, keeping %v", [
        quota,
        split.send_quota,
        split.keep_quota
    ]),
    "mutations": [
        {
            "block_type": constants.block_type_mesh_routing,
            "operation": "MUTATE_SPRAY_QUOTA",
            "local_quota": split.keep_quota,
            "local_phase": split.new_local_phase,
            "transmitted_quota": split.send_quota,
            "transmitted_phase": split.transmitted_phase
        }
    ]
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_entire_bundle(input.contact, input.bundle)
    quota := helpers.get_quota(block)
    quota >= 2
    helpers.get_spray_mode(block) == constants.spray_mode_binary
    split := helpers.calculate_binary_spray(quota)
}

# 5. Réplication / Spray and Wait : Phase SPRAY en mode SOURCE (L >= 2)
# La source distribue 1 copie au relais et conserve (L - 1)
decision := {
    "action": "FORWARD_REPLICATE",
    "reason": sprintf("Source spray: sending 1 copy (entering Wait on peer), keeping %v", [
        split.keep_quota
    ]),
    "mutations": [
        {
            "block_type": constants.block_type_mesh_routing,
            "operation": "MUTATE_SPRAY_QUOTA",
            "local_quota": split.keep_quota,
            "local_phase": split.new_local_phase,
            "transmitted_quota": 1,
            "transmitted_phase": constants.phase_wait
        }
    ]
} if {
    input.contact.peer_eid != input.bundle.primary.destination
    block := helpers.get_spray_block(input.bundle)
    not helpers.peer_already_holds_entire_bundle(input.contact, input.bundle)
    quota := helpers.get_quota(block)
    quota >= 2
    helpers.get_spray_mode(block) == constants.spray_mode_source
    split := helpers.calculate_source_spray(quota)
}

# 6. Contention Radio (Meshtastic) : Annulation de retransmission si entendu pendant la fenêtre de contention
decision := {
    "action": "SKIP",
    "reason": "Meshtastic rebroadcast cancelled: packet heard from another peer during backoff",
    "mutations": []
} if {
    msg_id := helpers.get_bundle_identifier(input.bundle)
    cancelled := object.get(input.node, "cancelled_rebroadcasts", [])
    is_cancelled(msg_id, input.bundle, cancelled)
}

# 7. Contention Radio (Meshtastic) : Diffusion radio après expiration du délai de contention
decision := {
    "action": "FORWARD_BROADCAST",
    "reason": "Packet ready for radio rebroadcast",
    "mutations": []
} if {
    input.contact.is_broadcast == true
    not helpers.get_spray_block(input.bundle)
    msg_id := helpers.get_bundle_identifier(input.bundle)
    cancelled := object.get(input.node, "cancelled_rebroadcasts", [])
    not is_cancelled(msg_id, input.bundle, cancelled)
}

is_cancelled(msg_id, _, cancelled) if {
    msg_id in cancelled
}

is_cancelled(_, bundle, cancelled) if {
    tuple_id := [bundle.primary.source, bundle.primary.creation_timestamp.time, bundle.primary.creation_timestamp.sequence_number]
    tuple_id in cancelled
}
