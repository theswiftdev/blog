build:
	toucan generate ./src ./

watch:
	toucan watch ./src ./ --base-url /

serve:
	LOG_LEVEL=notice toucan serve

# brew install optipng jpegoptim

png:
	find ./src/* -type f -name '*.png' -exec optipng -o7 {} \;

jpg:
	find ./* -type f -name '*.jpg' | xargs jpegoptim --all-progressive '*.jpg' 