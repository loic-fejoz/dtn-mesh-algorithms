package dtn.aprs.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.aprs.constants

# Récupère le bloc de routage mesh générique (Type 200)
get_mesh_block(bundle) := block if {
    some b in bundle.extension_blocks
    b.block_type == constants.block_type_mesh_routing
    block := b
}

# Alias pour compatibilité
get_aprs_block(bundle) := get_mesh_block(bundle)

# Récupère les données de contrôle de trajectoire (générique ou plat)
get_trajectory_payload(bundle) := payload if {
    block := get_mesh_block(bundle)
    payload := object.get(block.payload, "trajectory_control", block.payload)
}

# Extrait l'identifiant de déduplication (legacy_bridge_id, transaction_id ou dupe_suppression_hash)
get_transaction_id(bundle) := id if {
    block := get_mesh_block(bundle)
    id := object.get(block.payload, "legacy_bridge_id", object.get(block.payload, "transaction_id", object.get(block.payload, "dupe_suppression_hash", null)))
}

# Vérification du cache anti-doublon (Dupe Suppression Cache)
is_duplicate(bundle, seen_cache) if {
    id := get_transaction_id(bundle)
    id != null
    id in seen_cache
}

is_duplicate(bundle, seen_cache) if {
    canonical_id := [bundle.primary.source, bundle.primary.creation_timestamp.time, bundle.primary.creation_timestamp.sequence_number]
    canonical_id in seen_cache
}

# Récupère l'élément de saut actuellement actif dans la trajectoire
get_active_hop(payload) := hop if {
    idx := payload.active_hop_index
    idx < count(payload.path_elements)
    hop := payload.path_elements[idx]
}

# Type de saut : strict
is_strict_hop(hop) if {
    kind := object.get(hop, "target_type", object.get(hop, "hop_kind", 0))
    kind == constants.hop_kind_strict
}

# Type de saut : alias
is_alias_hop(hop) if {
    kind := object.get(hop, "target_type", object.get(hop, "hop_kind", 0))
    kind == constants.hop_kind_alias
}

get_target_id(hop) := id if {
    id := object.get(hop, "target_id", object.get(hop, "node_identifier", ""))
}

get_scope_name(hop) := name if {
    name := object.get(hop, "scope_name", object.get(hop, "alias_name", ""))
}

get_remaining_count(hop) := count_rem if {
    count_rem := object.get(hop, "remaining_count", object.get(hop, "remaining_hops", 0))
}

# Vérifie si le saut strict correspond à l'indicatif ou à l'EID du nœud local
is_strict_match(hop, node) if {
    is_strict_hop(hop)
    get_target_id(hop) == node.callsign
}

is_strict_match(hop, node) if {
    is_strict_hop(hop)
    get_target_id(hop) == node.local_eid
}

# Vérifie si un alias (ex: "WIDE1", "WIDE2") est pris en charge par le nœud
is_alias_supported(alias_name, supported_aliases) if {
    alias_name in supported_aliases
}

# Règle Dire Wolf 6.1(b) : Le paquet provient-il de la station locale elle-même ?
is_own_packet(bundle, node) if {
    bundle.primary.source == node.local_eid
}

is_own_packet(bundle, node) if {
    bundle.primary.source == node.callsign
}

# Recommandation Dire Wolf Section 10 : Trapping des alias excessifs (ex: WIDE3-3, WIDE4-4)
is_trapped_alias(alias_name, trapped_aliases) if {
    alias_name in trapped_aliases
}
