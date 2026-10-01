package dtn.geodtn_test

import future.keywords.if
import future.keywords.in

import data.dtn.geodtn.ingress
import data.dtn.geodtn.contact
import data.dtn.geodtn.storage
import data.dtn.geodtn.constants

mock_geo_bundle(dest, target_lat, target_lon, radius_deg, hops) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": dest,
        "source": "dtn://sar/drone-base/",
        "report_to": "dtn://sar/drone-base/",
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": 3600000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 10,
            "hop_limit": 10,
            "hop_count": hops
        },
        {
            "block_type": 200,
            "spatial_scope": {
                "center_lat_deg": target_lat,
                "center_lon_deg": target_lon,
                "radius_deg": radius_deg
            }
        }
    ]
}

# 1. Ingress : Livraison locale si la destination correspond à l'EID local
test_geodtn_ingress_local_delivery_by_eid if {
    input := {
        "bundle": mock_geo_bundle("dtn://sar/rescuer-1/", 45.75, 4.85, 0.0, 1),
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://sar/rescuer-1/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DELIVER_LOCAL"
}

# 2. Ingress : Livraison locale Geocast si le nœud est situé à l'intérieur de la zone cible
test_geodtn_ingress_local_delivery_by_geocast_location if {
    # Cible : lat 45.75, lon 4.85, rayon 0.05
    # Nœud : lat 45.76, lon 4.86 (distance au carré : 0.0002 <= 0.0025)
    input := {
        "bundle": mock_geo_bundle(constants.geocast_broadcast_eid, 45.75, 4.85, 0.05, 1),
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://sar/rescuer-2/",
            "coordinates": {"lat": 45.76, "lon": 4.86}
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DELIVER_LOCAL"
}

# 3. Ingress : Relais régulier si le nœud est hors de la zone Geocast
test_geodtn_ingress_geocast_outside_location_not_delivered_locally if {
    # Cible : lat 45.75, lon 4.85, rayon 0.01 (0.0001)
    # Nœud : lat 46.10, lon 5.20 (bien plus loin)
    input := {
        "bundle": mock_geo_bundle(constants.geocast_broadcast_eid, 45.75, 4.85, 0.01, 1),
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://sar/relay-node/",
            "coordinates": {"lat": 46.10, "lon": 5.20}
        }
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_FORWARD"
}

# 4. Ingress : Rejet si source blacklistée
test_geodtn_ingress_blacklisted_source if {
    input := {
        "bundle": mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 1),
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://sar/relay-node/",
            "blacklist_sources": ["dtn://sar/drone-base/"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.generate_status_report == false
}

# 5. Ingress : Rejet des doublons
test_geodtn_ingress_duplicate if {
    bundle := mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 1)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://sar/relay-node/",
            "seen_cache": ["dtn://sar/drone-base/:1000:1"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Duplicate bundle detected in seen cache"
}

# 6. Ingress : Rejet si durée de vie expirée
test_geodtn_ingress_expired if {
    bundle := mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 1)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 1000 + 3600000 + 1,
        "node": {"local_eid": "dtn://sar/relay-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Bundle lifetime expired"
}

# 7. Ingress : Rejet si Hop Limit atteint
test_geodtn_ingress_hop_limit_reached if {
    bundle := mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 10)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://sar/relay-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    contains(decision.reason, "Hop limit exceeded")
}

# 8. Ingress : Acceptation normale avec incrément de saut
test_geodtn_ingress_data_forward if {
    bundle := mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://sar/relay-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_FORWARD"
    decision.mutations[0].value == 3
}

# 9. Contact : Livraison directe à la destination EID
test_geodtn_contact_direct_destination if {
    bundle := mock_geo_bundle("dtn://sar/target-rescuer/", 45.75, 4.85, 0.0, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://sar/target-rescuer/",
            "is_broadcast": false
        },
        "node": {"local_eid": "dtn://sar/relay-node/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_DIRECT"
}

# 10. Contact : Routage glouton (Greedy Forwarding) vers un pair plus proche de la cible
test_geodtn_contact_greedy_closer_peer if {
    # Cible : lat 45.75, lon 4.85
    # Nœud local : lat 45.90, lon 4.90 (dist^2 = 0.0225 + 0.0025 = 0.0250)
    # Pair : lat 45.80, lon 4.86 (dist^2 = 0.0025 + 0.0001 = 0.0026 < 0.0250) -> PLUS PROCHE !
    bundle := mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://sar/drone-closer/",
            "is_broadcast": false,
            "coordinates": {"lat": 45.80, "lon": 4.86}
        },
        "node": {
            "local_eid": "dtn://sar/relay-node/",
            "coordinates": {"lat": 45.90, "lon": 4.90}
        }
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_GREEDY"
}

# 11. Contact : Minimum local (Local Void) — le pair est plus éloigné, rétention Store-Carry-and-Forward
test_geodtn_contact_skip_void_farther_peer if {
    # Cible : lat 45.75, lon 4.85
    # Nœud local : lat 45.80, lon 4.86 (plus proche)
    # Pair : lat 45.95, lon 5.10 (plus loin) -> cul-de-sac géographique !
    bundle := mock_geo_bundle("dtn://sar/target/", 45.75, 4.85, 0.0, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://sar/drone-farther/",
            "is_broadcast": false,
            "coordinates": {"lat": 45.95, "lon": 5.10}
        },
        "node": {
            "local_eid": "dtn://sar/relay-node/",
            "coordinates": {"lat": 45.80, "lon": 4.86}
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "Local minimum void")
}

# 12. Contact : Diffusion Geocast intra-zone (les deux nœuds sont dans le périmètre)
test_geodtn_contact_in_zone_geocast_flood if {
    # Cible : lat 45.75, lon 4.85, rayon 0.10
    # Nœud local et pair sont tous deux à l'intérieur du périmètre
    bundle := mock_geo_bundle(constants.geocast_broadcast_eid, 45.75, 4.85, 0.10, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://sar/rescuer-in-zone/",
            "is_broadcast": false,
            "coordinates": {"lat": 45.76, "lon": 4.86}
        },
        "node": {
            "local_eid": "dtn://sar/rescuer-relay/",
            "coordinates": {"lat": 45.74, "lon": 4.84}
        }
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_GEOCAST_IN_ZONE"
}

# 13. Contact : Nœud local dans la zone, mais pair en dehors et plus loin
test_geodtn_contact_skip_edge_peer_outside_zone if {
    bundle := mock_geo_bundle(constants.geocast_broadcast_eid, 45.75, 4.85, 0.02, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://sar/rescuer-outside/",
            "is_broadcast": false,
            "coordinates": {"lat": 46.00, "lon": 5.20} # Loin hors zone
        },
        "node": {
            "local_eid": "dtn://sar/rescuer-in-zone/",
            "coordinates": {"lat": 45.75, "lon": 4.85}
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
}

# 14. Contact : Évitement de boucle vers l'émetteur précédent (Split Horizon Type 6)
test_geodtn_contact_skip_previous_node if {
    bundle := {
        "primary": {
            "source": "dtn://sar/source/",
            "destination": "dtn://sar/dest/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000
        },
        "extension_blocks": [
            {
                "block_type": 6,
                "previous_node": "dtn://sar/prev-node/"
            },
            {
                "block_type": 200,
                "spatial_scope": {
                    "center_lat_deg": 45.75,
                    "center_lon_deg": 4.85,
                    "radius_deg": 0.0
                }
            }
        ]
    }
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://sar/prev-node/",
            "is_broadcast": false,
            "coordinates": {"lat": 45.75, "lon": 4.85}
        },
        "node": {
            "local_eid": "dtn://sar/current/",
            "coordinates": {"lat": 45.80, "lon": 4.90}
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "split horizon")
}

# 15. Storage : Destruction à expiration
test_geodtn_storage_drop_expired if {
    bundle := mock_geo_bundle("dtn://sar/dest/", 45.75, 4.85, 0.0, 2)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 1000 + 3600000 + 10
    }
    decision := storage.decision with input as input
    decision.action == "DROP"
}

# 16. Storage : Mise à jour de l'âge relatif pour bundle non synchronisé
test_geodtn_storage_retain_and_update_age if {
    bundle := {
        "primary": {
            "source": "dtn://sar/sensor/",
            "destination": "dtn://sar/dest/",
            "creation_timestamp": {"time": 0, "sequence_number": 1},
            "lifetime": 3600000,
            "processing_flags": {"deletion_report": false}
        },
        "extension_blocks": [{
            "block_type": 7,
            "bundle_age": 1000
        }]
    }
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "elapsed_since_last_audit_ms": 1000
    }
    decision := storage.decision with input as input
    decision.action == "RETAIN_AND_UPDATE_AGE"
    decision.mutations[0].added_ms == 1000
}
