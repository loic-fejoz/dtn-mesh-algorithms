package dtn.babel.helpers

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.babel.constants

# Vérifie si le bundle est un message de signalisation Babel
is_babel_control(bundle) if {
    bundle.primary.destination == constants.babel_broadcast_eid
}

is_babel_control(bundle) if {
    contains(bundle.primary.destination, "/babel")
}

# Vérifie si la destination correspond au nœud local
is_local_destination(destination, node) if {
    destination == node.local_eid
}

# Recherche de route dans la table de routage Babel du nœud local
default get_route_entry(_, _) := null

get_route_entry(destination, routing_table) := entry if {
    routing_table != null
    entry := object.get(routing_table, destination, null)
    entry != null
}

get_route_entry(destination, routing_table) := entry if {
    routing_table != null
    not object.get(routing_table, destination, null)
    some key, val in routing_table
    contains(destination, key)
    entry := val
}

# Vérifie si une entrée de routage est active et non expirée
is_route_valid(entry, current_time_ms) if {
    entry != null
    metric := object.get(entry, "metric", constants.metric_infinity)
    metric < constants.metric_infinity
    expires_at := object.get(entry, "expires_at_ms", 0)
    current_time_ms <= expires_at
}

# Condition de faisabilité de Babel (Feasibility Condition - RFC 8966 Section 3.5.1) :
# Une annonce avec métrique m est strictement sans boucle si m < Feasible Distance (FD).
is_metric_feasible(new_metric, feasible_distance) if {
    new_metric < feasible_distance
}

# Arbitrage de mise à jour de route selon l'algorithme Bellman-Ford sans boucle :
# 1. Aucune route existante
should_update_babel_route(existing_entry, _, _, _) if {
    existing_entry == null
}

# 2. La route existante a expiré ou a une métrique infinie
should_update_babel_route(existing_entry, _, _, current_time_ms) if {
    existing_entry != null
    not is_route_valid(existing_entry, current_time_ms)
}

# 3. Le numéro de séquence est strictement plus récent (seqno > old_seqno)
# En Babel, un seqno supérieur émis par le routeur d'origine réinitialise la métrique.
should_update_babel_route(existing_entry, new_seqno, new_metric, current_time_ms) if {
    existing_entry != null
    is_route_valid(existing_entry, current_time_ms)
    old_seqno := object.get(existing_entry, "seqno", 0)
    new_seqno > old_seqno
    new_metric < constants.metric_infinity
}

# 4. Même numéro de séquence, mais métrique strictement inférieure (chemin plus court)
should_update_babel_route(existing_entry, new_seqno, new_metric, current_time_ms) if {
    existing_entry != null
    is_route_valid(existing_entry, current_time_ms)
    old_seqno := object.get(existing_entry, "seqno", 0)
    new_seqno == old_seqno
    new_metric < existing_entry.metric
}

# Vérifie si la source figure dans la blacklist du nœud local
is_source_blacklisted(source_eid, node) if {
    base_helpers.is_source_blacklisted(source_eid, node)
}
