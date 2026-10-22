var mqtt = module("mqtt")
mqtt.connected = def () return true end
mqtt.publish = def (t, p, r) return true end
return mqtt
