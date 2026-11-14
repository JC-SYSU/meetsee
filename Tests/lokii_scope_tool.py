"""Verify scope-only source patches, including Unicode positions and multiline TOML."""
import pathlib, subprocess, sys, tempfile

updates = 'index_paths = ["/Applications", "/Users/example/资料"]\nexclude = []\nexclude_paths = ["/Users/example/资料/缓存"]\ninclude_hidden = true\nmax_results = 5000\n'
original = '''# 全局说明保持原样
[general]
language = "zh-Hans"
show_in_dock = true

[index] # 索引说明
"index_paths" = [
    "~", # 行内说明会随被替换的值更新
]
exclude = ["node_modules"] # 外部注释保留
exclude_paths = ["/System"]
include_hidden = false
max_results = 500
network_rescan_minutes = 5

[shortcut]
toggle_window = "Cmd+Shift+Space"
custom = """多行字符串
[index] 不是真实表头
"""
'''
with tempfile.TemporaryDirectory(prefix='meetsee-toml-tests-') as temp:
    config = pathlib.Path(temp) / 'config.toml'
    def patch(text):
        config.write_text(text)
        return subprocess.run([sys.argv[1], str(config)], input=updates, capture_output=True, text=True)
    changed = patch(original)
    assert changed.returncode == 0, changed.stderr
    result = changed.stdout
    assert result.startswith('# 全局说明保持原样\n[general]\nlanguage = "zh-Hans"')
    assert result[result.index('[shortcut]'):] == original[original.index('[shortcut]'):]
    assert '# 外部注释保留' in result and 'max_results = 5000' in result
    assert '/Users/example/资料' in result and 'node_modules' not in result and '"/System"' not in result
    # Already matching scope is byte-for-byte unchanged; no backup/write churn.
    assert patch(result).stdout == result
    for missing in ['[general]\nlanguage="zh-Hans"\n', '[index]\nmax_results=500\n[window]\nhide_on_blur=true\n', '[index]']:
        changed = patch(missing)
        assert changed.returncode == 0, changed.stderr
        assert 'index_paths' in changed.stdout and 'include_hidden = true' in changed.stdout
    assert patch('[index]\nindex_paths = [unterminated').returncode != 0
    assert patch('index = { index_paths = ["~"] }').returncode != 0
    assert config.read_text() == 'index = { index_paths = ["~"] }'  # Tool never writes input.
print('PASS: real TOML parser, source-preserving scope fields, quoted keys, Unicode, multiline arrays/strings, missing keys/table, no-op identity, invalid/inline rejection; unrelated settings untouched')
