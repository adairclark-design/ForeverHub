local addonName, ns = ...
ns = ns or _G.ForeverHub or {}
ns = ns or {}

ns.name = addonName or "ForeverHub"
ns.version = "0.8.7"

ns.Compat = ns.Compat or {}
ns.Data = ns.Data or {}
ns.RivergladesData = ns.RivergladesData or {}
ns.GoldFarmsData = ns.GoldFarmsData or {}
ns.State = ns.State or {}
ns.Providers = ns.Providers or {}
ns.Domain = ns.Domain or {}
ns.UI = ns.UI or {}
ns.Bridges = ns.Bridges or {}

-- Expose a single namespaced reference for diagnostics and /fh doctor without polluting _G
_G.ForeverHub = ns
