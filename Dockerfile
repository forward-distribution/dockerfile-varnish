# DO: Update TAGs in .circleci/config.yml
FROM forwardpublishing/ld-varnish-fp-security-update:6.5.2-r1

COPY custom.vcl.tmpl $VARNISH_CONFIG_TEMPLATE
