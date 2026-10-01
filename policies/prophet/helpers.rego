package dtn.prophet.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as dtn_helpers
import data.dtn.prophet.constants

# Récupère le bloc d'extension de routage mesh (Type 200)
get_mesh_block(bundle) := block if {
    some b in bundle.extension_blocks
    b.block_type == constants.block_type_mesh_routing
    block := b
}

# Extrait le seuil opportuniste requis par l'émetteur (si présent dans le bloc d'extension)
default get_opportunistic_threshold(_) := null

get_opportunistic_threshold(bundle) := threshold if {
    block := get_mesh_block(bundle)
    threshold := object.get(block.payload, "opportunistic_threshold", null)
    threshold != null
}

# Récupère la prévisibilité de livraison locale P(a, target)
get_local_predictability(node, target_eid) := p if {
    preds := object.get(node, "delivery_predictabilities", {})
    p := object.get(preds, target_eid, 0.0)
}

# Récupère la prévisibilité de livraison du pair P(b, target) reçue lors de la découverte CLA
get_peer_predictability(contact, target_eid) := p if {
    preds := object.get(contact, "peer_predictabilities", {})
    p := object.get(preds, target_eid, 0.0)
}

# --- Équations mathématiques PRoPHET (RFC 6693 Section 3) ---

# 1. Mise à jour lors d'une rencontre directe avec le nœud B :
# P(a, b) = P(a, b)_old + (1 - P(a, b)_old) * P_encounter
update_encounter(p_old, p_encounter) := p_new if {
    p_new := p_old + ((1.0 - p_old) * p_encounter)
}

# Calcul de décroissance temporelle (gamma ^ time_units) sans récursion
compute_decay(gamma, time_units) := 1.0 if {
    time_units <= 0
}

compute_decay(gamma, 1) := gamma

compute_decay(gamma, 2) := gamma * gamma

compute_decay(gamma, 3) := (gamma * gamma) * gamma

compute_decay(gamma, time_units) := decay if {
    time_units >= 4
    g2 := gamma * gamma
    decay := g2 * g2
}

# 2. Vieillissement temporel de la prévisibilité :
# P(a, b) = P(a, b)_old * (gamma ^ time_units)
update_aging(p_old, gamma, time_units) := p_new if {
    decay := compute_decay(gamma, time_units)
    p_new := p_old * decay
}

# 3. Propriété de transitivité :
# Lorsque A rencontre B, pour tout C connu de B :
# P(a, c) = P(a, c)_old + (1 - P(a, c)_old) * P(a, b) * P(b, c) * beta
update_transitivity(p_ac_old, p_ab, p_bc, beta) := p_ac_new if {
    transitive_factor := (p_ab * p_bc) * beta
    p_ac_new := p_ac_old + ((1.0 - p_ac_old) * transitive_factor)
}

# Vérifie si le bundle a déjà été vu par le nœud (cache anti-doublon)
is_bundle_seen(bundle, seen_cache) if {
    canonical_id := dtn_helpers.get_bundle_id(bundle)
    canonical_id in seen_cache
}

is_bundle_seen(bundle, seen_cache) if {
    tuple_id := [bundle.primary.source, bundle.primary.creation_timestamp.time, bundle.primary.creation_timestamp.sequence_number]
    tuple_id in seen_cache
}

# Vérifie si le contact possède déjà le bundle (via Summary Vector)
peer_already_holds_bundle(contact, bundle) if {
    canonical_id := dtn_helpers.get_bundle_id(bundle)
    held := object.get(contact, "held_bundle_ids", [])
    canonical_id in held
}

peer_already_holds_bundle(contact, bundle) if {
    tuple_id := [bundle.primary.source, bundle.primary.creation_timestamp.time, bundle.primary.creation_timestamp.sequence_number]
    held := object.get(contact, "held_bundle_ids", [])
    tuple_id in held
}

peer_already_holds_bundle(contact, bundle) if {
    block := get_mesh_block(bundle)
    legacy_id := object.get(block.payload, "legacy_bridge_id", null)
    legacy_id != null
    held := object.get(contact, "held_bundle_ids", [])
    legacy_id in held
}

# Condition de forwarding PRoPHET :
# Le pair rencontré a une prévisibilité strictement supérieure à celle du nœud local (avec marge)
is_forwarding_favorable(p_peer, p_local, margin) if {
    p_peer > (p_local + margin)
}

# Vérification du respect du seuil opportuniste exigé par le bundle
satisfies_threshold(p_peer, threshold) if {
    threshold == null
}

satisfies_threshold(p_peer, threshold) if {
    threshold != null
    p_peer >= threshold
}
