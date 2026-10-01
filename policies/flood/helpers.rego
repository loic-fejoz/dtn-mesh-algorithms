package dtn.flood.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.flood.constants
import data.dtn.helpers as base_helpers

# Recherche d'un bloc d'extension mesh
get_mesh_block(bundle) := block if {
    some b in bundle.extension_blocks
    b.block_type == constants.block_type_mesh_routing
    block := b
}

# Recherche pour la dimension Réplication (Spray & Wait, etc.)
get_spray_block(bundle) := block if {
    some b in bundle.extension_blocks
    b.block_type == constants.block_type_mesh_routing
    is_replication_block(b)
    block := b
}

is_replication_block(b) if { b.algo_type == constants.algo_spray_and_wait }
is_replication_block(b) if { _ := b.payload.replication_control }
is_replication_block(b) if { _ := b.payload.replication_quota }

# Accesseurs génériques pour la dimension Réplication
get_quota(block) := q if {
    rep := object.get(block.payload, "replication_control", block.payload)
    q := object.get(rep, "quota", object.get(rep, "replication_quota", 0))
}

get_spray_mode(block) := m if {
    rep := object.get(block.payload, "replication_control", block.payload)
    m := object.get(rep, "mode", object.get(rep, "spray_mode", constants.spray_mode_binary))
}

# Récupère l'identifiant pour déduplication / annulation :
# 1. Soit un legacy_bridge_id dans le bloc d'extension
# 2. Soit l'identifiant canonique BPv7 (Source, Time, Seq)
get_bundle_identifier(bundle) := id if {
    some b in bundle.extension_blocks
    b.block_type == constants.block_type_mesh_routing
    id := object.get(b.payload, "legacy_bridge_id", object.get(b.payload, "transaction_id", object.get(b.payload, "message_id", object.get(b.payload, "packet_id", null))))
    id != null
} else := id if {
    id := base_helpers.get_bundle_id(bundle)
}

# Accesseur de secours pour compatibilité avec anciens fixtures
get_msg_id(block) := id if {
    id := object.get(block.payload, "legacy_bridge_id", object.get(block.payload, "transaction_id", object.get(block.payload, "message_id", object.get(block.payload, "packet_id", null))))
}

# Détection de doublon via cache de messages vus
is_duplicate(msg_id, seen_cache) if {
    msg_id in seen_cache
}

is_bundle_duplicate(bundle, seen_cache) if {
    id := get_bundle_identifier(bundle)
    id in seen_cache
}

is_bundle_duplicate(bundle, seen_cache) if {
    tuple_id := [bundle.primary.source, bundle.primary.creation_timestamp.time, bundle.primary.creation_timestamp.sequence_number]
    tuple_id in seen_cache
}

# Filtrage par whitelist d'EID de destination (remplace avantageusement le channel_hash)
is_destination_allowed(destination, node) if {
    allowed := object.get(node, "allowed_destinations", null)
    allowed == null # Aucune whitelist configurée : tout est accepté
}

is_destination_allowed(destination, node) if {
    allowed := object.get(node, "allowed_destinations", null)
    allowed != null
    destination in allowed
}

# Vérifie si le contact possède déjà une copie du bundle
peer_already_holds_bundle(contact, bundle_id) if {
    held := object.get(contact, "held_bundle_ids", [])
    bundle_id in held
}

peer_already_holds_entire_bundle(contact, bundle) if {
    id := get_bundle_identifier(bundle)
    held := object.get(contact, "held_bundle_ids", [])
    id in held
}

peer_already_holds_entire_bundle(contact, bundle) if {
    tuple_id := [bundle.primary.source, bundle.primary.creation_timestamp.time, bundle.primary.creation_timestamp.sequence_number]
    held := object.get(contact, "held_bundle_ids", [])
    tuple_id in held
}

# Calcul de la division de quota binaire pour Spray & Wait
calculate_binary_spray(quota) := result if {
    quota >= 2
    to_send := floor(quota / 2)
    to_keep := quota - to_send
    result := {
        "send_quota": to_send,
        "keep_quota": to_keep,
        "new_local_phase": phase_for_quota(to_keep),
        "transmitted_phase": phase_for_quota(to_send)
    }
}

# Calcul de la division de quota source pour Spray & Wait
calculate_source_spray(quota) := result if {
    quota >= 2
    to_send := 1
    to_keep := quota - 1
    result := {
        "send_quota": to_send,
        "keep_quota": to_keep,
        "new_local_phase": phase_for_quota(to_keep),
        "transmitted_phase": constants.phase_wait
    }
}

# Détermine la phase (SPRAY si L > 1, WAIT si L == 1)
phase_for_quota(quota) := constants.phase_spray if {
    quota > 1
}

phase_for_quota(quota) := constants.phase_wait if {
    quota <= 1
}

# Calcul du délai de contention Meshtastic basé sur le SNR (en dB)
calculate_meshtastic_backoff(snr_db) := delay_ms if {
    clamped_snr := max([snr_db + 15, 0])
    delay_ms := constants.meshtastic_base_backoff_ms + round(clamped_snr * constants.meshtastic_snr_factor_ms)
}
