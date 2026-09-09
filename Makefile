.PHONY: images check

# Regenerate the docs images from the script's own output. Run this after
# changing a colour or a threshold — the SVGs are generated, not screenshotted,
# so they stay honest only if you regenerate them.
images:
	python3 scripts/render_svg.py

# Verify the copies of statusline.sh and tree.md embedded in docs/design.md
# still match the real files.
check:
	@python3 -c "import pathlib,re,sys; \
b=pathlib.Path('.'); doc=(b/'docs/design.md').read_text(); ok=True; \
pairs=[(r\"cat > ~/\.claude/statusline\.sh <<'SH'\n(.*?)\nSH\n\", 'statusline.sh'), \
       (r\"cat > ~/\.claude/commands/tree\.md <<'EOF'\n(.*?)\nEOF\n\", 'commands/tree.md')]; \
[print(f'{n}: ' + ('OK' if (re.search(p,doc,re.S).group(1)+chr(10))==(b/n).read_text() else 'DRIFT')) for p,n in pairs]"
