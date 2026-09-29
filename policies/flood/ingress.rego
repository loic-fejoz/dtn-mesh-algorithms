package dtn.flood.ingress

import future.keywords.if
import future.keywords.in

import data.dtn.constants as base_constants
import data.dtn.helpers as base_helpers
import data.dtn.flood.constants
import data.dtn.flood.helpers

# Décision par défaut : DROP
default decision := {
    "action": "DROP",
    "reason": "Default flood ingress rule",
    "mutations": []
}

# 1. Livraison locale si la destination est le nœud local
decision := {
    "action": "DELIVER_LOCAL",
    "reason": "Destination matches local node",
    "mutations": []
} if {
    input.bundle.primary.destination == input.node.local_eid
}

# 2. Suppression de doublon (Flooding / Epidemic loop prevention)
decision := {
    "action": "DROP",
    "reason": "Duplicate message detected in seen cache",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    helpers.is_bundle_duplicate(input.bundle, input.node.seen_cache)
}

# 3. Filtrage par Whitelist d'EID de destination (remplace le channel_hash physique)
decision := {
    "action": "DROP",
    "reason": "Destination EID not allowed by local node whitelist",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_bundle_duplicate(input.bundle, input.node.seen_cache)
    not helpers.is_destination_allowed(input.bundle.primary.destination, input.node)
}

# 4. Ingress Réplication / Quotas (Spray and Wait)
decision := {
    "action": "ACCEPT_STORE",
    "reason": sprintf("Replication bundle accepted with quota L=%v (Phase: %v)", [
        quota,
        phase_name(quota)
    ]),
    "mutations": [
        {
            "block_type": constants.block_type_mesh_routing,
            "operation": "SET_SPRAY_STATE",
            "phase": helpers.phase_for_quota(quota),
            "quota": quota,
            "replication_quota": quota,
            "cache_id": msg_id
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_bundle_duplicate(input.bundle, input.node.seen_cache)
    helpers.is_destination_allowed(input.bundle.primary.destination, input.node)
    block := helpers.get_spray_block(input.bundle)
    msg_id := helpers.get_bundle_identifier(input.bundle)
    quota := helpers.get_quota(block)
}

# 5. Ingress Contention Radio : Rejet si le Hop Count Block (Type 10) atteint la limite
decision := {
    "action": "DROP",
    "reason": "Hop limit exceeded (BPv7 Hop Count Block Type 10)",
    "mutations": []
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_bundle_duplicate(input.bundle, input.node.seen_cache)
    helpers.is_destination_allowed(input.bundle.primary.destination, input.node)
    base_helpers.will_exceed_hop_limit(input.bundle)
}

# 6. Ingress Contention Radio (Meshtastic) : Acceptation, calcul du backoff SNR et incrémentation Hop Count Type 10
decision := {
    "action": "ACCEPT_REBROADCAST",
    "reason": sprintf("Packet accepted for rebroadcast (SNR: %v dB, backoff: %v ms, hop %v/%v)", [
        snr_db,
        delay_ms,
        hop_block.hop_count + 1,
        hop_block.hop_limit
    ]),
    "mutations": [
        {
            "operation": "SET_RADIO_BACKOFF",
            "backoff_delay_ms": delay_ms,
            "cache_id": msg_id
        },
        {
            "block_type": base_constants.block_type_hop_count,
            "operation": "SET_FIELD",
            "field": "hop_count",
            "value": hop_block.hop_count + 1
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_bundle_duplicate(input.bundle, input.node.seen_cache)
    helpers.is_destination_allowed(input.bundle.primary.destination, input.node)
    not helpers.get_spray_block(input.bundle)
    not base_helpers.will_exceed_hop_limit(input.bundle)
    hop_block := base_helpers.get_hop_count_block(input.bundle)
    msg_id := helpers.get_bundle_identifier(input.bundle)
    snr_db := get_snr(input)
    delay_ms := helpers.calculate_meshtastic_backoff(snr_db)
}

# 7. Ingress Contention Radio : Acceptation si aucun Hop Count Block n'est présent (mode permissif)
decision := {
    "action": "ACCEPT_REBROADCAST",
    "reason": sprintf("Packet accepted for rebroadcast (no Hop Count block, SNR: %v dB, backoff: %v ms)", [
        snr_db,
        delay_ms
    ]),
    "mutations": [
        {
            "operation": "SET_RADIO_BACKOFF",
            "backoff_delay_ms": delay_ms,
            "cache_id": msg_id
        }
    ]
} if {
    input.bundle.primary.destination != input.node.local_eid
    not helpers.is_bundle_duplicate(input.bundle, input.node.seen_cache)
    helpers.is_destination_allowed(input.bundle.primary.destination, input.node)
    not helpers.get_spray_block(input.bundle)
    not base_helpers.get_hop_count_block(input.bundle)
    msg_id := helpers.get_bundle_identifier(input.bundle)
    snr_db := get_snr(input)
    delay_ms := helpers.calculate_meshtastic_backoff(snr_db)
}

# Helper SNR extrait de la télémétrie locale d'entrée (input.ingress)
get_snr(inp) := snr if {
    snr := inp.ingress.snr_db
}

get_snr(inp) := snr if {
    not inp.ingress.snr_db
    snr := 0.0
}

phase_name(quota) := "WAIT" if { quota <= 1 }
phase_name(quota) := "SPRAY" if { quota > 1 }
