package dtn.reticulum.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.reticulum.constants

# Vérifie si le bundle est une annonce de routage Reticulum
is_announce(bundle) if {
    bundle.primary.destination == constants.announce_broadcast_eid
}

is_announce(bundle) if {
    contains(bundle.primary.destination, "/announce")
}

# Vérifie si la destination correspond au nœud local
# Prend en charge soit la correspondance d'EID exacte, soit le hash local Reticulum
is_local_destination(destination, node) if {
    destination == node.local_eid
}

is_local_destination(destination, node) if {
    local_hash := object.get(node, "reticulum_destination_hash", null)
    local_hash != null
    contains(destination, local_hash)
}

# Récupère l'entrée de table de routage associée à la destination
default get_route_entry(_, _) := null

get_route_entry(destination, routing_table) := entry if {
    routing_table != null
    entry := object.get(routing_table, destination, null)
    entry != null
}

# Recherche par sous-chaîne ou hash si l'EID est au format URI "dtn://rns/<hash>/"
get_route_entry(destination, routing_table) := entry if {
    routing_table != null
    not object.get(routing_table, destination, null)
    some key, val in routing_table
    contains(destination, key)
    entry := val
}

# Vérifie si une entrée de routage est encore temporellement valide
is_route_valid(entry, current_time_ms) if {
    entry != null
    expires_at := object.get(entry, "expires_at_ms", 0)
    current_time_ms <= expires_at
}

# Condition de mise à jour d'un chemin Reticulum (Distance Vector) :
# Une nouvelle annonce met à jour la table si :
# 1. Aucun chemin connu vers cette destination
# 2. Le chemin existant a expiré
# 3. La nouvelle annonce propose un chemin plus court (métrique en sauts inférieure)
should_update_path(existing_entry, new_hops, current_time_ms) if {
    existing_entry == null
}

should_update_path(existing_entry, _, current_time_ms) if {
    existing_entry != null
    not is_route_valid(existing_entry, current_time_ms)
}

should_update_path(existing_entry, new_hops, current_time_ms) if {
    existing_entry != null
    is_route_valid(existing_entry, current_time_ms)
    new_hops < existing_entry.hops
}

# Vérifie si l'EID source figure dans la blacklist du nœud local
is_source_blacklisted(source_eid, node) if {
    base_helpers.is_source_blacklisted(source_eid, node)
}
