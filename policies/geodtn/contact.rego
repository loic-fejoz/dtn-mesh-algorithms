package dtn.geodtn.contact

import future.keywords.if
import future.keywords.in

import data.dtn.helpers as base_helpers
import data.dtn.geodtn.constants
import data.dtn.geodtn.helpers

default decision := {
    "action": "SKIP",
    "reason": "Default GeoDTN contact rule",
    "mutations": []
}

# 1. Contact direct avec la destination finale (EID unicast)
decision := {
    "action": "FORWARD_DIRECT",
    "reason": "Peer matches final destination endpoint",
    "mutations": []
} if {
    not input.contact.is_broadcast
    input.contact.peer_eid == input.bundle.primary.destination
}

# 2. Expiration de durée de vie avant transmission
decision := {
    "action": "DROP",
    "reason": "Bundle lifetime expired prior to forwarding",
    "generate_status_report": base_helpers.is_deletion_report_requested(input.bundle),
    "mutations": []
} if {
    base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
}

# 3. Évitement de boucle immédiate (Split Horizon - Type 6)
decision := {
    "action": "SKIP",
    "reason": "Skip proximate sender node (split horizon)",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
}

# 4. Diffusion dans la zone cible (In-Zone Geocast Flooding) :
# Lorsque le bundle a atteint le périmètre géographique visé, il est rediffusé
# à tous les pairs présents à l'intérieur du cercle d'action.
decision := {
    "action": "FORWARD_GEOCAST_IN_ZONE",
    "reason": "Geocast perimeter reached: broadcasting bundle to peer located inside target zone",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    helpers.is_geocast(input.bundle)
    scope := helpers.get_spatial_scope(input.bundle)
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    my_coords != null
    peer_coords != null
    
    radius := object.get(scope, "radius_deg", 0.01)
    helpers.is_inside_perimeter(my_coords.lat, my_coords.lon, scope.center_lat_deg, scope.center_lon_deg, radius)
    helpers.is_inside_perimeter(peer_coords.lat, peer_coords.lon, scope.center_lat_deg, scope.center_lon_deg, radius)
}

# 5. Routage glouton (Greedy Forwarding) :
# Le pair est physiquement plus proche des coordonnées cibles que le nœud local
decision := {
    "action": "FORWARD_GREEDY",
    "reason": "Greedy geographic forwarding: peer is closer to target spatial coordinates",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    not is_in_zone_geocast_active(input)
    
    scope := helpers.get_spatial_scope(input.bundle)
    scope != null
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    my_coords != null
    peer_coords != null
    
    helpers.is_peer_closer(peer_coords, my_coords, scope.center_lat_deg, scope.center_lon_deg)
}

# 6. Cul-de-sac géographique / Minimum local (Local Void) :
# Le pair est plus éloigné ou à même distance de la cible. En DTN, on n'abandonne
# pas le bundle : on le conserve en stockage physique (Greedy-Carry-and-Forward).
decision := {
    "action": "SKIP",
    "reason": "Local minimum void: peer is not closer to target coordinates, holding bundle (Greedy-Carry-and-Forward)",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    not is_in_zone_geocast_active(input)
    
    scope := helpers.get_spatial_scope(input.bundle)
    scope != null
    
    my_coords := object.get(input.node, "coordinates", null)
    peer_coords := object.get(input.contact, "coordinates", null)
    
    is_not_closer(peer_coords, my_coords, scope)
}

# 7. Absence de coordonnées ou de portée spatiale
decision := {
    "action": "SKIP",
    "reason": "Missing spatial scope or coordinates in geographic evaluation",
    "mutations": []
} if {
    not base_helpers.is_lifetime_expired(input.bundle, input.current_dtn_time_ms)
    not base_helpers.is_previous_node(input.bundle, input.contact.peer_eid)
    input.contact.peer_eid != input.bundle.primary.destination
    helpers.get_spatial_scope(input.bundle) == null
}

# Prédicats d'aide
is_in_zone_geocast_active(inp) if {
    helpers.is_geocast(inp.bundle)
    scope := helpers.get_spatial_scope(inp.bundle)
    my_coords := object.get(inp.node, "coordinates", null)
    peer_coords := object.get(inp.contact, "coordinates", null)
    my_coords != null
    peer_coords != null
    radius := object.get(scope, "radius_deg", 0.01)
    helpers.is_inside_perimeter(my_coords.lat, my_coords.lon, scope.center_lat_deg, scope.center_lon_deg, radius)
    helpers.is_inside_perimeter(peer_coords.lat, peer_coords.lon, scope.center_lat_deg, scope.center_lon_deg, radius)
}

is_not_closer(peer_coords, my_coords, scope) if {
    peer_coords != null
    my_coords != null
    not helpers.is_peer_closer(peer_coords, my_coords, scope.center_lat_deg, scope.center_lon_deg)
}

is_not_closer(null, _, _) if true
is_not_closer(_, null, _) if true
