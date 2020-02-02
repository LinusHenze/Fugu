all:
	mkdir -p build
	cd "t8010 t8011 loader" && $(MAKE)
	cd iStrap && $(MAKE)

%:
	mkdir -p build
	cd "t8010 t8011 loader" && $(MAKE) $@
	cd iStrap && $(MAKE) $@
