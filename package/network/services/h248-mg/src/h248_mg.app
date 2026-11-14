{application, h248_mg,
 [{description, "Minimal H.248/Megaco media gateway"},
  {vsn, "0.1"},
  {modules, [h248_mg, h248_rtp, h248_sdp, h248_g711]},
  {registered, []},
  {applications, [kernel, stdlib, megaco]},
  {mod, {h248_mg, []}}
 ]}.
