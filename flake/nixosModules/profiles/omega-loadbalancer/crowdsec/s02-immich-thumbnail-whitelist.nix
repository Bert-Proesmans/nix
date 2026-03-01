# NOTE; This processor drops matching log lines before they reach scenario processors.
# WARN; This processor must run during enrich stage!
#
# NOTE; Test processor with 'cscli explain'-command
# cscli explain --log '<logstring content>' --type <nginx/haproxy/etc> --verbose
#
# NOTE; Find more stuff to whitelist by inspecting crowdsec alerts
# cscli alerts inspect <ALERT_ID> --details
{
  name = "bertp/immich-thumbnail-whitelist";
  description = "Whitelist client early abort on streaming video thumbnails";
  filter = "evt.Meta.service == 'http' && evt.Meta.log_type in ['http_access-log', 'http_error-log']";
  whitelist =
    let
      # WARN; Expression =/= Grok aka it's not possible to use defined patterns inside expression regex!
      UUID_pattern = "[A-Fa-f0-9]{8}-(?:[A-Fa-f0-9]{4}-){3}[A-Fa-f0-9]{12}";
    in
    {
      reason = "Early abort GET <asset>/<thumbnail>";
      expression = [
        # eg /api/assets/3f43e1e8-8360-416e-a0cd-e3694ccb4054/thumbnail?size=thumbnail&c=nRgGE4KBmB9SqvQNn3z4yWY%3D&edited=true
        "evt.Meta.http_verb == 'GET' && evt.Meta.http_status == '400' && evt.Meta.http_path matches '/api/assets/${UUID_pattern}/thumbnail'"
        # eg /api/assets/85095e95-619c-448b-9f06-ec32a4f408f2/video/playback?c=XQgKBQDlmw9hx12Gqol5h49y90hI
        "evt.Meta.http_verb == 'GET' && evt.Meta.http_status == '400' && evt.Meta.http_path matches '/api/assets/${UUID_pattern}/video/playback'"
      ];
    };
}
