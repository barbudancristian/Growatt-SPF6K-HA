var mqtt = module("mqtt")
mqtt.connected = def () return true end
mqtt.publish = def (t, p, r) PUBS[t] = p return true end
return mqtt
