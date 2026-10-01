package dtn.maxprop.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.maxprop.constants

# Vérifie si le bundle est un message de signalisation MaxProp
is_maxprop_control(bundle) if {
    bundle.primary.destination == constants.maxprop_broadcast_eid
}

is_maxprop_control(bundle) if {
    contains(bundle.primary.destination, "/maxprop")
}

# Vérifie si la destination correspond au nœud local
is_local_destination(destination, node) if {
    destination == node.local_eid
}

# Vérifie si le bundle a déjà été acquitté et figure dans la Cleared List
is_bundle_cleared(bundle, cleared_list) if {
    cleared_list != null
    canonical_id := base_helpers.get_bundle_id(bundle)
    canonical_id in cleared_list
}

# Calcul du coût de tri de file d'attente (HP-MaxProp) :
# Coût_Tri = Coût_Dijkstra + 0.01 * HopCount
compute_sorting_cost(dijkstra_cost, hop_count) := dijkstra_cost + (constants.hop_penalty_factor * hop_count)

# Récupère le coût de chemin vers la destination dans la table de coût locale
default get_path_cost(_, _) := 9999.0

get_path_cost(destination, cost_table) := cost if {
    cost_table != null
    cost := object.get(cost_table, destination, constants.cost_infinity)
}

# Vérifie si l'émetteur figure dans la blacklist du nœud
is_source_blacklisted(source_eid, node) if {
    base_helpers.is_source_blacklisted(source_eid, node)
}
