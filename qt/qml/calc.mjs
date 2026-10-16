// Calculatrice du lanceur : + − × ÷ % ^, parenthèses, fonctions usuelles.
// Analyse descendante récursive : aucun eval().

const FN = {
  sqrt: Math.sqrt, racine: Math.sqrt, abs: Math.abs, round: Math.round, floor: Math.floor, ceil: Math.ceil,
  sin: Math.sin, cos: Math.cos, tan: Math.tan, asin: Math.asin, acos: Math.acos, atan: Math.atan,
  ln: Math.log, log: Math.log10, exp: Math.exp,
};
const CONST = { pi: Math.PI, π: Math.PI, e: Math.E };

function tokens(src) {
  const out = [];
  const re = /\s*(?:(\d+(?:[.,]\d+)?(?:e[+-]?\d+)?|[.,]\d+)|([a-zπ]+)|(\*\*|[-+*/%^()x×÷]))/gi;
  let m;
  while (re.lastIndex < src.length) {
    const at = re.lastIndex;
    m = re.exec(src);
    if (!m || m.index !== at) {
      if (/^\s*$/.test(src.slice(at))) break;
      return null;
    }
    if (m[1]) out.push({ n: parseFloat(m[1].replace(',', '.')) });
    else if (m[2]) {
      const w = m[2].toLowerCase();
      if (w === 'x') out.push({ op: '*' });
      else out.push({ id: w });
    } else out.push({ op: { '×': '*', 'x': '*', '÷': '/', '**': '^' }[m[3]] || m[3] });
  }
  return out;
}

export function calc(src) {
  const t = tokens(src);
  if (!t || !t.length) return null;
  let i = 0;
  const peek = () => t[i];
  const isOp = o => peek() && peek().op === o;

  function primary() {
    const tok = t[i++];
    if (!tok) throw 0;
    if (tok.n !== undefined) return tok.n;
    if (tok.op === '(') {
      const v = expr();
      if (!isOp(')')) throw 0;
      i++;
      return v;
    }
    if (tok.op === '-') return -power();
    if (tok.op === '+') return power();
    if (tok.id) {
      if (tok.id in CONST) return CONST[tok.id];
      if (tok.id in FN) {
        const arg = isOp('(') ? primary() : power();
        return FN[tok.id](arg);
      }
    }
    throw 0;
  }
  function power() {
    let v = primary();
    if (isOp('^')) { i++; v = Math.pow(v, unary()); }
    return v;
  }
  function unary() {
    if (isOp('-')) { i++; return -unary(); }
    if (isOp('+')) { i++; return unary(); }
    return power();
  }
  function term() {
    let v = unary();
    for (;;) {
      if (isOp('*')) { i++; v *= unary(); }
      else if (isOp('/')) { i++; v /= unary(); }
      else if (isOp('%')) { i++; v %= unary(); }
      // multiplication implicite : 2(3+1), 2pi
      else if (peek() && (peek().op === '(' || peek().id)) v *= unary();
      else return v;
    }
  }
  function expr() {
    let v = term();
    for (;;) {
      if (isOp('+')) { i++; v += term(); }
      else if (isOp('-')) { i++; v -= term(); }
      else return v;
    }
  }
  try {
    const v = expr();
    if (i !== t.length || !Number.isFinite(v)) return null;
    return v;
  } catch (e) {
    return null;
  }
}

/// Vrai si le texte ressemble à un calcul (pour l'afficher sans le préfixe =).
export function looksLikeMath(s) {
  return /^[\d(.,πa-z\s]/i.test(s) && /\d/.test(s) && /[-+*/%^×÷x(]/.test(s.replace(/^[-+]/, '')) && calc(s) !== null;
}

export function fmtNumber(v) {
  if (Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0)) return v.toExponential(6).replace('.', ',');
  // comme toLocaleString('fr-FR') : espace fine insecable entre les milliers, virgule
  const n = Number(v.toPrecision(12));
  const neg = n < 0;
  let [int, dec] = Math.abs(n).toFixed(10).replace(/0+$/, '').split('.');
  int = int.replace(/\B(?=(\d{3})+(?!\d))/g, String.fromCharCode(0x202f));
  return (neg ? '-' : '') + int + (dec ? ',' + dec : '');
}
