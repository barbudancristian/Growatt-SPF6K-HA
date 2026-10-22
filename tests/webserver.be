var webserver = module("webserver")
webserver.out = ""
webserver.args = {}
webserver.routes = {}
webserver.BUTTON_MAIN = 0
webserver.BUTTON_CONFIGURATION = 1
webserver.HTTP_GET = 1
webserver.HTTP_POST = 2
webserver.content_send = def (s) webserver.out += s end
webserver.content_start = def (t) webserver.out = "<title>" + t + "</title>" end
webserver.content_send_style = def () end
webserver.content_button = def (b) end
webserver.content_stop = def () end
webserver.check_privileged_access = def () return true end
webserver.html_escape = def (s) return s end
webserver.has_arg = def (k) return webserver.args.contains(k) end
webserver.arg = def (k) return webserver.args.find(k, "") end
webserver.on = def (p, f, m) webserver.routes[p + str(m)] = f end
return webserver
