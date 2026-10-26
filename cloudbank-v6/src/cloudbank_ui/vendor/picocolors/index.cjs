// Copyright (c) 2026, Oracle and/or its affiliates.
//
// Licensed under the Universal Permissive License v 1.0 as shown at
// https://oss.oracle.com/licenses/upl/.

// Local compatibility layer for the terminal highlighting used by PostCSS.
// Styling is deliberately omitted; this does not affect generated CSS.
const identity = value => String(value);
const colors = {
  isColorSupported: false,
  reset: identity, bold: identity, dim: identity, italic: identity, underline: identity,
  inverse: identity, hidden: identity, strikethrough: identity,
  black: identity, red: identity, green: identity, yellow: identity, blue: identity,
  magenta: identity, cyan: identity, white: identity, gray: identity,
  bgBlack: identity, bgRed: identity, bgGreen: identity, bgYellow: identity,
  bgBlue: identity, bgMagenta: identity, bgCyan: identity, bgWhite: identity,
};
colors.createColors = () => colors;
module.exports = colors;
