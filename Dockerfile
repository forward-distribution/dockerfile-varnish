# FROM livingdocs/varnish:6.4.0-r3
FROM forwardpublishing/ld-varnish-fp-security-update:6.5.2-r1
COPY custom.vcl.tmpl $VARNISH_CONFIG_TEMPLATE
