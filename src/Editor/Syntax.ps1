$ErrorActionPreference = 'Stop'

#region Language Detection
function Get-LanguageFromPath([string]$path) {
  if ([string]::IsNullOrEmpty($path)) { return 'Plain Text' }
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    '.ps1' { 'PowerShell' } '.psm1' { 'PowerShell' } '.psd1' { 'PowerShell' }
    '.cs' { 'C#' }
    '.ts' { 'TypeScript' } '.tsx' { 'TypeScript' }
    '.js' { 'JavaScript' } '.jsx' { 'JavaScript' }
    '.py' { 'Python' }
    '.json' { 'JSON' } '.jsonc' { 'JSONC' } '.jsonl' { 'JSON' }
    '.md' { 'Markdown' }
    '.sh' { 'Bash' } '.bash' { 'Bash' }
    '.html' { 'HTML' } '.htm' { 'HTML' }
    '.css' { 'CSS' }
    '.svg' { 'SVG' }
    '.yaml' { 'YAML' } '.yml' { 'YAML' }
    '.toml' { 'TOML' }
    '.java' { 'Java' }
    default {
      if ($path -match '\.env') { 'dotenv' }
      elseif ($path -match 'Dockerfile') { 'Dockerfile' }
      else { 'Plain Text' }
    }
  }
#endregion
#region Syntax Rules
$script:languageSyntaxRules = @{
  "JavaScript" = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|\\.)*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('`(?:[^`\\]|\\.)*`', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|while|do|switch|case|break|continue|return|function|var|let|const|class|extends|new|this|super|import|export|default|from|as|async|await|try|catch|finally|throw)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null|undefined)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_$][\w$]*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "TypeScript" = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|\\.)*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('`(?:[^`\\]|\\.)*`', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|while|do|switch|case|break|continue|return|function|var|let|const|class|extends|new|this|super|import|export|default|from|as|async|await|try|catch|finally|throw|interface|type|enum)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null|undefined)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_$][\w$]*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "Python"     = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('(''[\s\S]*?''|"""[\s\S]*?""")', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|\\.)*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|elif|else|for|while|def|class|import|from|as|return|yield|with|try|except|finally|raise|break|continue|pass|and|or|not|in|is|None|True|False)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_]\w*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "PowerShell" = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('<#[\s\S]*?#>', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new("'(?:[^']|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|elseif|foreach|for|while|do|switch|case|default|return|break|continue|function|filter|param|begin|process|end|throw|try|catch|finally|trap|class|enum|using|namespace|in|and|or|not)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\$\w+', 'Compiled'); TokenType = 'variable' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[\+\-\*\/%<>=!&|^~]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "Bash"       = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^']|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|then|else|elif|fi|for|while|do|done|case|esac|function|return|exit|source|export|local|readonly|declare|shift|trap|break|continue)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\$\{?\w+', 'Compiled'); TokenType = 'variable' }
    @{ CompiledRegex = [regex]::new('\b\d+\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[+\-*/%<>=!&|^~]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "HTML"       = @(
    @{ CompiledRegex = [regex]::new('<!--[\s\S]*?-->', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('</?[a-zA-Z0-9]+', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('[{}><]', 'Compiled'); TokenType = 'punctuation' }
  )
  "CSS"        = @(
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('#[0-9a-fA-F]{3,8}', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?(px|em|rem|%|vw|vh)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[{};:]', 'Compiled'); TokenType = 'punctuation' }
  )
  "SVG"        = @(
    @{ CompiledRegex = [regex]::new('<!--[\s\S]*?-->', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('</?[a-zA-Z_:][\w:.-]*', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('[{}><]', 'Compiled'); TokenType = 'punctuation' }
  )
  "JSON"       = @(
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[{}[\],:]', 'Compiled'); TokenType = 'punctuation' }
  )
  "JSONC"      = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[{}[\],:]', 'Compiled'); TokenType = 'punctuation' }
  )
  "YAML"       = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^']|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[\[\]{}:>|]', 'Compiled'); TokenType = 'punctuation' }
  )
  "TOML"       = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'(?:[^'\\]|'')*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(true|false)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('-?\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[\[\]{}.,=]', 'Compiled'); TokenType = 'punctuation' }
  )
  "dotenv"     = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"[^"]*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new("'[^']*'", 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[=]', 'Compiled'); TokenType = 'operator' }
  )
  "Java"       = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|while|do|switch|case|break|continue|return|class|interface|extends|implements|new|this|super|import|package|try|catch|finally|throw|throws|public|private|protected|static|final|void|int|long|double|boolean|char|byte|short|float|String)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_]\w*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[+\-*/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "C#"         = @(
    @{ CompiledRegex = [regex]::new('//.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('/\*[\s\S]*?\*/', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(if|else|for|foreach|while|do|switch|case|break|continue|return|class|struct|interface|enum|namespace|using|new|this|base|public|private|protected|internal|static|readonly|virtual|override|abstract|sealed|async|await|try|catch|finally|throw|int|long|float|double|decimal|bool|char|string|var|void|object|dynamic)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\b(true|false|null)\b', 'Compiled'); TokenType = 'constant' }
    @{ CompiledRegex = [regex]::new('\b\d+(\.\d+)?([eE][+-]?\d+)?\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('\b[A-Z][a-zA-Z0-9_]*\b', 'Compiled'); TokenType = 'type' }
    @{ CompiledRegex = [regex]::new('\b[a-zA-Z_]\w*(?=\s*[\(])', 'Compiled'); TokenType = 'function' }
    @{ CompiledRegex = [regex]::new('[+\-*/%<>=!&|^~?:]+', 'Compiled'); TokenType = 'operator' }
    @{ CompiledRegex = [regex]::new('[.,;{}\[\]()]', 'Compiled'); TokenType = 'punctuation' }
  )
  "Markdown"   = @(
    @{ CompiledRegex = [regex]::new('^#{1,6}.*$', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\[.*?\]\(.*?\)', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('`{1,3}[^`]*`{1,3}', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('^[*-+]\s.*$', 'Compiled'); TokenType = 'punctuation' }
  )
  "Dockerfile" = @(
    @{ CompiledRegex = [regex]::new('#.*$', 'Compiled'); TokenType = 'comment' }
    @{ CompiledRegex = [regex]::new('"(?:[^"\\]|\\.)*"', 'Compiled'); TokenType = 'string' }
    @{ CompiledRegex = [regex]::new('\b(FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|SHELL)\b', 'Compiled'); TokenType = 'keyword' }
    @{ CompiledRegex = [regex]::new('\$\{?\w+\}?', 'Compiled'); TokenType = 'variable' }
    @{ CompiledRegex = [regex]::new('\b\d+\b', 'Compiled'); TokenType = 'number' }
    @{ CompiledRegex = [regex]::new('[=]', 'Compiled'); TokenType = 'operator' }
  )
}

#endregion
#region Tokenizer
function Get-TokensForLine([string]$line, [string]$language) {
  if (-not $script:languageSyntaxRules.ContainsKey($language)) { return @() }
  $rules = $script:languageSyntaxRules[$language]
  $tokenList = [System.Collections.Generic.List[object]]::new()
  $pos = 0
  while ($pos -lt $line.Length) {
    $best = $null
    foreach ($rule in $rules) {
      $m = $rule.CompiledRegex.Match($line, $pos)
      if ($m.Success -and $m.Index -eq $pos -and ($null -eq $best -or $m.Length -gt $best.Length)) {
        $best = @{ Start = $pos; Length = $m.Length; Type = $rule.TokenType }
      }
    }
    if ($best) { $tokenList.Add([PSCustomObject]$best); $pos += $best.Length }
    else { $pos++ }
  }
  return $tokenList
}

#endregion
#region Accessors
function Get-LanguageSyntaxRules {
  return $script:languageSyntaxRules
}
#endregion