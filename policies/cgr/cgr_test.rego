package dtn.cgr_test

import future.keywords.if
import future.keywords.in

import data.dtn.cgr.ingress
import data.dtn.cgr.contact
import data.dtn.cgr.storage
import data.dtn.cgr.constants

mock_data_bundle(src, dest, creation_time, lifetime, size_bytes) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": dest,
        "source": src,
        "report_to": src,
        "creation_timestamp": {"time": creation_time, "sequence_number": 1},
        "lifetime": lifetime,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 10,
            "hop_limit": 10,
            "hop_count": 1
        }
    ],
    "total_size_bytes": size_bytes
}

mock_cgr_control_bundle(contacts) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": constants.cgr_broadcast_eid,
        "source": "dtn://space/mission-control/",
        "report_to": "dtn://none",
        "creation_timestamp": {"time": 1000, "sequence_number": 2},
        "lifetime": 86400000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [{
        "block_type": 10,
        "hop_limit": 5,
        "hop_count": 0
    }],
    "contact_plan": contacts
}

# 1. Ingress : Livraison locale si la destination correspond à l'EID local
test_cgr_ingress_local_delivery if {
    input := {
        "bundle": mock_data_bundle("dtn://earth/ground-station/", "dtn://mars/rover-alpha/", 1000, 3600000, 2048),
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://mars/rover-alpha/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DELIVER_LOCAL"
}

# 2. Ingress : Rejet silencieux si la source est blacklistée
test_cgr_ingress_blacklisted_source if {
    input := {
        "bundle": mock_data_bundle("dtn://rogue/transmitter/", "dtn://mars/rover-alpha/", 1000, 3600000, 2048),
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://mars/rover-alpha/",
            "blacklist_sources": ["dtn://rogue/transmitter/"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.generate_status_report == false
}

# 3. Ingress : Rejet des doublons
test_cgr_ingress_duplicate if {
    bundle := mock_data_bundle("dtn://earth/ground-station/", "dtn://mars/orbiter/", 1000, 3600000, 2048)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://mars/relay/",
            "seen_cache": ["dtn://earth/ground-station/:1000:1"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Duplicate bundle detected in seen cache"
}

# 4. Ingress : Rejet si durée de vie expirée
test_cgr_ingress_expired if {
    bundle := mock_data_bundle("dtn://earth/ground-station/", "dtn://mars/orbiter/", 1000, 5000, 2048)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 7000,
        "node": {"local_eid": "dtn://mars/relay/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Bundle lifetime expired"
}

# 5. Ingress : Rejet si Hop limit atteint
test_cgr_ingress_hop_limit_reached if {
    bundle := {
        "primary": {
            "source": "dtn://earth/gs/",
            "destination": "dtn://mars/dest/",
            "creation_timestamp": {"time": 1000, "sequence_number": 1},
            "lifetime": 3600000
        },
        "extension_blocks": [{
            "block_type": 10,
            "hop_limit": 5,
            "hop_count": 5
        }]
    }
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://mars/relay/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    contains(decision.reason, "Hop limit exceeded")
}

# 6. Ingress : Ingestion d'une mise à jour de Contact Plan CGR
test_cgr_ingress_contact_plan_update if {
    contacts := [{
        "contact_id": 101,
        "from_eid": "dtn://earth/gs/",
        "to_eid": "dtn://mars/orbiter/",
        "start_time_ms": 5000,
        "end_time_ms": 15000,
        "data_rate_bps": 1000000
    }]
    bundle := mock_cgr_control_bundle(contacts)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://mars/relay/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_CONTACT_PLAN_UPDATE"
    decision.mutations[0].operation == "UPDATE_CONTACT_PLAN"
}

# 7. Ingress : Ingestion d'un bundle de données standard avec incrément de saut
test_cgr_ingress_data_forward if {
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/orbiter/", 1000, 3600000, 1024)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://mars/relay/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_FORWARD"
    decision.mutations[0].field == "hop_count"
    decision.mutations[0].value == 2
}

# 8. Contact : Livraison directe à la destination finale
test_cgr_contact_direct_destination if {
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/rover/", 1000, 3600000, 1024)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://mars/rover/",
            "is_broadcast": false
        },
        "node": {"local_eid": "dtn://mars/relay/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_DIRECT"
}

# 9. Contact : Rediffusion des messages de signalisation CGR en broadcast
test_cgr_contact_control_broadcast if {
    bundle := mock_cgr_control_bundle([])
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://broadcast/cgr",
            "is_broadcast": true
        },
        "node": {"local_eid": "dtn://mars/relay/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_BROADCAST"
}

# 10. Contact : Forward déterministe lors d'une fenêtre de contact CGR active
test_cgr_contact_forward_scheduled_active if {
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/target/", 1000, 3600000, 2048)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 6000, # Fenêtre ouverte entre 5000 et 10000
        "contact": {
            "peer_eid": "dtn://relay/orbiter-1/",
            "is_broadcast": false,
            "scheduled_contact": {
                "contact_id": 42,
                "start_time_ms": 5000,
                "end_time_ms": 10000
            }
        },
        "node": {
            "local_eid": "dtn://earth/gs/",
            "cgr_routes": {
                "dtn://mars/target/": {
                    "destination_eid": "dtn://mars/target/",
                    "next_hop_eid": "dtn://relay/orbiter-1/",
                    "first_contact_id": 42,
                    "earliest_delivery_time_ms": 8000,
                    "remaining_capacity_bytes": 1000000,
                    "hops": 2
                }
            }
        }
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_CGR_SCHEDULED"
    decision.mutations[0].operation == "DECREMENT_CONTACT_CAPACITY"
    decision.mutations[0].bytes == 2048
}

# 11. Contact : Ignorer le pair s'il n'est pas le prochain saut désigné
test_cgr_contact_skip_non_next_hop if {
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/target/", 1000, 3600000, 2048)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 6000,
        "contact": {
            "peer_eid": "dtn://other/orbiter/",
            "is_broadcast": false
        },
        "node": {
            "local_eid": "dtn://earth/gs/",
            "cgr_routes": {
                "dtn://mars/target/": {
                    "next_hop_eid": "dtn://relay/orbiter-1/",
                    "earliest_delivery_time_ms": 8000,
                    "remaining_capacity_bytes": 1000000
                }
            }
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "not designated next-hop")
}

# 12. Contact : Fenêtre de contact pas encore ouverte (Start Time dans le futur)
test_cgr_contact_skip_window_not_yet_open if {
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/target/", 1000, 3600000, 2048)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 3000, # Fenêtre s'ouvre à 5000
        "contact": {
            "peer_eid": "dtn://relay/orbiter-1/",
            "is_broadcast": false,
            "scheduled_contact": {
                "contact_id": 42,
                "start_time_ms": 5000,
                "end_time_ms": 10000
            }
        },
        "node": {
            "local_eid": "dtn://earth/gs/",
            "cgr_routes": {
                "dtn://mars/target/": {
                    "next_hop_eid": "dtn://relay/orbiter-1/",
                    "first_contact_id": 42,
                    "earliest_delivery_time_ms": 8000,
                    "remaining_capacity_bytes": 1000000
                }
            }
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "not currently open")
}

# 13. Contact : Capacité restante insuffisante dans la fenêtre de contact
test_cgr_contact_skip_insufficient_capacity if {
    # Bundle fait 50 000 octets, capacité restante 10 000 octets
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/target/", 1000, 3600000, 50000)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 6000,
        "contact": {
            "peer_eid": "dtn://relay/orbiter-1/",
            "is_broadcast": false,
            "scheduled_contact": {
                "contact_id": 42,
                "start_time_ms": 5000,
                "end_time_ms": 10000
            }
        },
        "node": {
            "local_eid": "dtn://earth/gs/",
            "cgr_routes": {
                "dtn://mars/target/": {
                    "next_hop_eid": "dtn://relay/orbiter-1/",
                    "first_contact_id": 42,
                    "earliest_delivery_time_ms": 8000,
                    "remaining_capacity_bytes": 10000
                }
            }
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
}

# 14. Storage : Rétention normale pour un contact planifié futur
test_cgr_storage_retain_scheduled if {
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/target/", 1000, 3600000, 1024)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://earth/gs/",
            "cgr_routes": {
                "dtn://mars/target/": {
                    "earliest_delivery_time_ms": 50000,
                    "remaining_capacity_bytes": 100000
                }
            }
        }
    }
    decision := storage.decision with input as input
    decision.action == "RETAIN"
}

# 15. Storage : Abandon préventif déterministe (EDT excède la durée de vie du bundle)
test_cgr_storage_drop_infeasible_schedule if {
    # Expiry time = 1000 + 10000 = 11000 ms. Mais EDT = 50000 ms ! Impossible d'arriver à temps.
    bundle := mock_data_bundle("dtn://earth/gs/", "dtn://mars/target/", 1000, 10000, 1024)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://earth/gs/",
            "cgr_routes": {
                "dtn://mars/target/": {
                    "earliest_delivery_time_ms": 50000,
                    "remaining_capacity_bytes": 100000
                }
            }
        }
    }
    decision := storage.decision with input as input
    decision.action == "DROP_INFEASIBLE_SCHEDULE"
    contains(decision.reason, "Earliest Delivery Time exceeds")
}

# 16. Storage : Mise à jour de l'âge pour bundle non synchronisé
test_cgr_storage_retain_and_update_age if {
    bundle := {
        "primary": {
            "source": "dtn://earth/gs/",
            "destination": "dtn://mars/target/",
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
        "elapsed_since_last_audit_ms": 500,
        "node": {"local_eid": "dtn://earth/gs/"}
    }
    decision := storage.decision with input as input
    decision.action == "RETAIN_AND_UPDATE_AGE"
    decision.mutations[0].added_ms == 500
}
