package dtn.babel_test

import future.keywords.if
import future.keywords.in

import data.dtn.babel.ingress
import data.dtn.babel.contact
import data.dtn.babel.storage
import data.dtn.babel.constants

# Bundle de données standard vers un nœud AREDN
mock_data_bundle(dest, hops) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": dest,
        "source": "dtn://aredn/source-node/",
        "report_to": "dtn://aredn/source-node/",
        "creation_timestamp": {"time": 1000, "sequence_number": 1},
        "lifetime": 3600000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [
        {
            "block_type": 10,
            "hop_limit": 15,
            "hop_count": hops
        }
    ]
}

# Bundle de contrôle Babel (UPDATE)
mock_babel_update_bundle(prefix, metric, seqno) := {
    "primary": {
        "version": 7,
        "bundle_processing_control_flags": 0,
        "destination": constants.babel_broadcast_eid,
        "source": "dtn://aredn/router-alpha/",
        "report_to": "dtn://none",
        "creation_timestamp": {"time": 1000, "sequence_number": 2},
        "lifetime": 60000,
        "processing_flags": {"deletion_report": false}
    },
    "extension_blocks": [{
        "block_type": 10,
        "hop_limit": 5,
        "hop_count": 0
    }],
    "babel_update": {
        "prefix_eid": prefix,
        "router_id": "0123456789abcdef",
        "seqno": seqno,
        "metric": metric,
        "interval_ms": 4000
    }
}

# 1. Ingress : Livraison locale si la destination correspond à l'EID local
test_babel_ingress_local_delivery if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/local-node/", 1),
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://aredn/local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DELIVER_LOCAL"
}

# 2. Ingress : Rejet silencieux si la source est blacklistée
test_babel_ingress_blacklisted_source if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/other-node/", 1),
        "current_dtn_time_ms": 2000,
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "blacklist_sources": ["dtn://aredn/source-node/"]
        }
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.generate_status_report == false
}

# 3. Ingress : Rejet si durée de vie expirée
test_babel_ingress_expired if {
    bundle := mock_data_bundle("dtn://aredn/other-node/", 1)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 1000 + 3600000 + 1,
        "node": {"local_eid": "dtn://aredn/local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    decision.reason == "Bundle lifetime expired"
}

# 4. Ingress : Rejet si Hop Limit atteint
test_babel_ingress_hop_limit_reached if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/other-node/", 15),
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://aredn/local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "DROP"
    contains(decision.reason, "Hop limit exceeded")
}

# 5. Ingress : Ingestion d'une nouvelle route via Babel UPDATE
test_babel_ingress_update_new_route if {
    bundle := mock_babel_update_bundle("dtn://aredn/target-service/", 50, 100)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "ingress": {
            "peer_eid": "dtn://aredn/router-alpha/",
            "link_cost": 20,
            "babel_update": bundle.babel_update
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {}
        }
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_BABEL_UPDATE"
    mutation := decision.mutations[0]
    mutation.operation == "UPDATE_ROUTING_TABLE"
    mutation.prefix_eid == "dtn://aredn/target-service/"
    mutation.next_hop == "dtn://aredn/router-alpha/"
    mutation.metric == 70 # 50 + 20
    mutation.seqno == 100
}

# 6. Ingress : Mise à jour de route sur un numéro de séquence plus récent (Seqno supérieur)
test_babel_ingress_update_newer_seqno if {
    bundle := mock_babel_update_bundle("dtn://aredn/target-service/", 80, 105)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "ingress": {
            "peer_eid": "dtn://aredn/router-alpha/",
            "link_cost": 20,
            "babel_update": bundle.babel_update
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {
                "dtn://aredn/target-service/": {
                    "next_hop_eid": "dtn://aredn/router-alpha/",
                    "metric": 50,
                    "seqno": 100,
                    "feasible_distance": 50,
                    "expires_at_ms": 50000
                }
            }
        }
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_BABEL_UPDATE"
    mutation := decision.mutations[0]
    mutation.seqno == 105
    mutation.metric == 100 # 80 + 20
}

# 7. Ingress : Même numéro de séquence mais métrique plus basse (chemin plus court)
test_babel_ingress_update_lower_metric_same_seqno if {
    bundle := mock_babel_update_bundle("dtn://aredn/target-service/", 20, 100)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "ingress": {
            "peer_eid": "dtn://aredn/router-beta/",
            "link_cost": 10,
            "babel_update": bundle.babel_update
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {
                "dtn://aredn/target-service/": {
                    "next_hop_eid": "dtn://aredn/router-alpha/",
                    "metric": 60,
                    "seqno": 100,
                    "feasible_distance": 60,
                    "expires_at_ms": 50000
                }
            }
        }
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_BABEL_UPDATE"
    mutation := decision.mutations[0]
    mutation.next_hop == "dtn://aredn/router-beta/"
    mutation.metric == 30 # 20 + 10 < 60
}

# 8. Ingress : Rejet d'une mise à jour avec métrique dégradée sur le même seqno
test_babel_ingress_update_worse_metric_ignored if {
    bundle := mock_babel_update_bundle("dtn://aredn/target-service/", 60, 100)
    input := {
        "bundle": bundle,
        "current_dtn_time_ms": 2000,
        "ingress": {
            "peer_eid": "dtn://aredn/router-gamma/",
            "link_cost": 20,
            "babel_update": bundle.babel_update
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {
                "dtn://aredn/target-service/": {
                    "next_hop_eid": "dtn://aredn/router-alpha/",
                    "metric": 50,
                    "seqno": 100,
                    "feasible_distance": 50,
                    "expires_at_ms": 50000
                }
            }
        }
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_BABEL_UPDATE_NO_CHANGE"
}

# 9. Ingress : Ingestion d'un bundle de données standard avec incrément de saut
test_babel_ingress_data_forward if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/target-service/", 3),
        "current_dtn_time_ms": 2000,
        "node": {"local_eid": "dtn://aredn/local-node/"}
    }
    decision := ingress.decision with input as input
    decision.action == "ACCEPT_FORWARD"
    mutation := decision.mutations[0]
    mutation.field == "hop_count"
    mutation.value == 4
}

# 10. Contact : Livraison directe à la destination finale
test_babel_contact_direct_destination if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/target-node/", 2),
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://aredn/target-node/",
            "is_broadcast": false
        },
        "node": {"local_eid": "dtn://aredn/local-node/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_DIRECT"
}

# 11. Contact : Rediffusion des messages de contrôle Babel en broadcast
test_babel_contact_control_broadcast if {
    input := {
        "bundle": mock_babel_update_bundle("dtn://aredn/target-service/", 20, 100),
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://broadcast/babel",
            "is_broadcast": true
        },
        "node": {"local_eid": "dtn://aredn/local-node/"}
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_BROADCAST"
}

# 12. Contact : Forwarding unicast vers le Prochain Saut désigné dans la table
test_babel_contact_forward_matching_next_hop if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/target-service/", 2),
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://aredn/router-alpha/",
            "is_broadcast": false
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {
                "dtn://aredn/target-service/": {
                    "next_hop_eid": "dtn://aredn/router-alpha/",
                    "metric": 35,
                    "seqno": 100,
                    "expires_at_ms": 50000
                }
            }
        }
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_NEXT_HOP"
}

# 13. Contact : Ignorer un pair qui n'est pas le prochain saut désigné
test_babel_contact_skip_non_next_hop_peer if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/target-service/", 2),
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://aredn/router-other/",
            "is_broadcast": false
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {
                "dtn://aredn/target-service/": {
                    "next_hop_eid": "dtn://aredn/router-alpha/",
                    "metric": 35,
                    "seqno": 100,
                    "expires_at_ms": 50000
                }
            }
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "is not designated next-hop")
}

# 14. Contact : Hybridation HYMAD — Destination inconnue dans l'îlot local,
# mais pair est un transporteur/ferry DTN inter-îlots !
test_babel_contact_hymad_dtn_carrier_bridging if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/remote-island-dest/", 2),
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://ferry/mobile-vehicle/",
            "is_broadcast": false,
            "is_dtn_carrier": true
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {} # Aucune route dans l'îlot AREDN local
        }
    }
    decision := contact.decision with input as input
    decision.action == "FORWARD_DTN_CARRIER"
}

# 15. Contact : Destination sans route et pair ordinaire -> Rétention
test_babel_contact_skip_isolated_unknown_route if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/remote-island-dest/", 2),
        "current_dtn_time_ms": 2000,
        "contact": {
            "peer_eid": "dtn://aredn/neighbor-no-carrier/",
            "is_broadcast": false,
            "is_dtn_carrier": false
        },
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "routing_table": {}
        }
    }
    decision := contact.decision with input as input
    decision.action == "SKIP"
    contains(decision.reason, "holding bundle")
}

# 16. Storage : Déclenchement d'une demande de route Babel si route manquante
test_babel_storage_trigger_route_request if {
    input := {
        "bundle": mock_data_bundle("dtn://aredn/unknown-target/", 2),
        "current_dtn_time_ms": 2000,
        "elapsed_since_last_audit_ms": 1000,
        "node": {
            "local_eid": "dtn://aredn/local-node/",
            "enable_babel_requests": true,
            "routing_table": {}
        }
    }
    decision := storage.decision with input as input
    decision.action == "RETAIN_AND_REQUEST_ROUTE"
    mutation := decision.mutations[0]
    mutation.operation == "TRIGGER_BABEL_ROUTE_REQUEST"
    mutation.prefix_eid == "dtn://aredn/unknown-target/"
}
