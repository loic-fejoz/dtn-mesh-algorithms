package dtn.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.constants

# Recherche un bloc d'extension par son type numérique
get_extension_block(blocks, block_type) := block if {
    some b in blocks
    b.block_type == block_type
    block := b
}

# Détection de l'expiration de la durée de vie (Lifetime)
# Gère deux cas conformes à la RFC 9171 :
# 1. Horloge synchronisée (creation_time > 0) : comparée au temps courant DTN
# 2. Horloge non synchronisée (creation_time == 0) : vérification via le Bundle Age Block (Type 7)
is_lifetime_expired(bundle, current_dtn_time_ms) if {
    bundle.primary.creation_timestamp.time > 0
    expiration_time := bundle.primary.creation_timestamp.time + bundle.primary.lifetime
    current_dtn_time_ms >= expiration_time
}

is_lifetime_expired(bundle, _) if {
    bundle.primary.creation_timestamp.time == 0
    age_block := get_extension_block(bundle.extension_blocks, constants.block_type_bundle_age)
    age_block.bundle_age_ms >= bundle.primary.lifetime
}

# Vérification du Hop Count Block (Type 10)
# Renvoie le bloc de saut s'il est présent
get_hop_count_block(bundle) := get_extension_block(bundle.extension_blocks, constants.block_type_hop_count)

# Indique si le hop count a atteint ou dépassé la limite autorisée.
# Note de conception (RFC 9171 Section 4.3.3) : la RFC stipule la suppression lorsque hop_count
# dépasse le hop_limit. L'utilisation du comparateur `>=` applique une politique conservatrice
# (adoptée par ION et dtn7) pour éviter l'émission inutile de paquets en limite sur les canaux contraints.
is_hop_limit_reached(bundle) if {
    hcb := get_hop_count_block(bundle)
    hcb.hop_count >= hcb.hop_limit
}

# Indique si l'incrément de saut (+1) atteindra ou dépassera la limite
will_exceed_hop_limit(bundle) if {
    hcb := get_hop_count_block(bundle)
    (hcb.hop_count + 1) >= hcb.hop_limit
}

# Vérifie si le bundle requiert un rapport d'état en cas de suppression
default is_deletion_report_requested(_) := false

is_deletion_report_requested(bundle) := true if {
    # Vérifie si le flag deletion_report est explicitement mis à true
    bundle.primary.processing_flags.deletion_report == true
}

is_deletion_report_requested(bundle) := true if {
    # Masque bitwise si un entier brut est passé pour bundle_processing_control_flags
    bits.and(bundle.primary.bundle_processing_control_flags, constants.flag_report_deletion) != 0
}

# Identifiant canonique unique d'un bundle BPv7 (RFC 9171 Section 4.2.2)
# Tuple d'identification universel : (Source EID, Creation Time, Sequence Number)
get_bundle_id(bundle) := sprintf("%v:%v:%v", [
    bundle.primary.source,
    bundle.primary.creation_timestamp.time,
    bundle.primary.creation_timestamp.sequence_number
])

# Vérifie si le nœud donné correspond au Previous Node Insertion Block (Type 6)
is_previous_node(bundle, peer_eid) if {
    pib := get_extension_block(bundle.extension_blocks, constants.block_type_previous_node)
    pib.previous_node == peer_eid
}

# Vérifie si l'EID source figure dans la liste noire (blacklist) du nœud local
is_source_blacklisted(source_eid, node) if {
    blacklist := object.get(node, "blacklist_sources", [])
    source_eid in blacklist
}
