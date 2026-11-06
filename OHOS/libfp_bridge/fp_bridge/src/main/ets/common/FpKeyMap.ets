// OHOS keycode → Unicode character (US layout).
// Shared by the XComponent key handler and the hidden TextInput handlers.
// 2000='0', 2001-2009='1'-'9', 2010='*', 2011='#', 2017-2042='A'-'Z',
// 2043=',' 2044='.' 2050=space 2056-2066=symbol keys.
// Shift selects the upper character.
export function ohosKeyToUnicode(kc: number, shift: boolean): number {
  if (kc === 2000) return shift ? ')'.charCodeAt(0) : '0'.charCodeAt(0);
  if (kc >= 2001 && kc <= 2009) {
    const base = String.fromCharCode('1'.charCodeAt(0) + (kc - 2001));
    if (!shift) return base.charCodeAt(0);
    const up = '!@#$%^&*(';
    return up.charCodeAt(kc - 2001);
  }
  if (kc === 2010) return '*'.charCodeAt(0);   // KEYCODE_STAR
  if (kc === 2011) return '#'.charCodeAt(0);   // KEYCODE_POUND
  if (kc >= 2017 && kc <= 2042) {
    const base = String.fromCharCode('a'.charCodeAt(0) + (kc - 2017));
    return shift ? base.toUpperCase().charCodeAt(0) : base.charCodeAt(0);
  }
  if (kc === 2043) return shift ? '<'.charCodeAt(0) : ','.charCodeAt(0);
  if (kc === 2044) return shift ? '>'.charCodeAt(0) : '.'.charCodeAt(0);
  if (kc === 2050) return ' '.charCodeAt(0);
  if (kc === 2056) return shift ? '~'.charCodeAt(0) : '`'.charCodeAt(0);
  if (kc === 2057) return shift ? '_'.charCodeAt(0) : '-'.charCodeAt(0);
  if (kc === 2058) return shift ? '+'.charCodeAt(0) : '='.charCodeAt(0);
  if (kc === 2059) return shift ? '{'.charCodeAt(0) : '['.charCodeAt(0);
  if (kc === 2060) return shift ? '}'.charCodeAt(0) : ']'.charCodeAt(0);
  if (kc === 2061) return shift ? '|'.charCodeAt(0) : '\\'.charCodeAt(0);
  if (kc === 2062) return shift ? ':'.charCodeAt(0) : ';'.charCodeAt(0);
  if (kc === 2063) return shift ? '"'.charCodeAt(0) : '\''.charCodeAt(0);
  if (kc === 2064) return shift ? '?'.charCodeAt(0) : '/'.charCodeAt(0);
  if (kc === 2065) return '@'.charCodeAt(0);
  if (kc === 2066) return '+'.charCodeAt(0);
  return 0;
}
