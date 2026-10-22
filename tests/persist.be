var persist = module("persist")
persist.find = def (k, d) return d end
persist.save = def () end
return persist
