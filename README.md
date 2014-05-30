# pct-coding — A set of functions to deal with percent-encoded data

Percent-encoding is a part of the IETF URI standard, [RFC3986][uri]. It is usually
viewed—and is arguably primarily defined—as an escaping mechanism for URIs to
permit characters such as ’/’ to appear without taking on their normal syntactic
significance. The percent-encoding mechanism has also, historically, been used
to embed non-ASCII characters from various single-byte encodings into URIs. This
further developed into the use of percent-encoded UTF-8 sequences embedded in
URIs, a usage formally specified in [RFC3987][iri]. Dealing with URIs as
anything more than simple strings more or less requires coping with this
mechanism, whether it is to escape the characters not allowed to appear in URIs
or to translate a substring of a URI or IRI into useful form.

[uri]: https://tools.ietf.org/html/rfc3986 "Uniform Resource Identifier (URI): Generic Syntax"
[iri]: https://tools.ietf.org/html/rfc3987 "Internationalized Resource Identifiers (IRIs)"

There is a complication, however. Sequences of percent-encoded bytes do _not_
have to be valid UTF-8, neither in URIs _nor_ IRIs. The simple way to deal with
this problem is to ignore it: Decode it as UTF-8 anyway, and if it contains
something invalid, just barf. This works for most situations. Another approach
is to translate IRIs to URIs and never try to go the other way. The problem here
is, essentially, that percent-encoding doesn’t encode character strings, it
encodes arbitrary binary data.

Me, I wanted to normalise arbitrary IRIs, which involves decoding the valid
UTF-8 sequences, but leaving invalid bytes encoded. I found no existing
percent-encoding tool that made this possible. So I wrote one. It exports three
functions and one constant. They all have what I believe to be decent
docstrings, but here’s a summary anyway:

`pct-decode` takes a percent-encoded string and turns it into an
octet-vector. It also takes two keyword arguments, `:encoding` and
`:reserved`. `:encoding` controls how characters not allowed to appear directly
in URIs are coded into bytes. It uses Babel, so `babel:list-character-encodings`
tells you what you can use. The default is UTF-8, which produces
IRIs. `:reserved` is a mechanism for normalisation: It takes a sequence of
characters whose percent-encodings should not be decoded, but left in the byte
sequence as-is.

`pct-encode` takes an octet-vector and turns it into an percent-encoded
string. It also takes three keyword arguments, `:iri`, `:reserved` and
`:ignore-existing`. `:iri` controls whether or not to attempt to reconstitute
UTF-8 sequences into Unicode characters in the resulting string. It defaults to
`t`, which makes the output valid as an IRI but not as an URI. `:reserved` is
essentially the opposite of the decoding version: It’s a sequence of characters
that should be percent-encoded in the resulting string, rather than appearing
directly. It defaults to `+uri-reserved+`. Finally, `:ignore-existing` will
leave any already percent-encoded sequence in the result string.

`pct-normalize` uses the two prior functions in a specific setup to normalise
the provided string. It accepts `:encoding` with the semantics of decode, `:iri`
with the semantics of encode, and `:reserved` with its own: A character, allowed
in URIs, found in the sequence passed will neither be decoded nor encoded by the
routine. That is: Reserved characters appearing directly in the source string
will appear directly in the result, and those appearing encoded in the source
string will remain encoded in the result. Its defaults are similar to those of
the other functions: assume characters represent their UTF-8 sequences, return
IRIs, and leave the URI reserved characters alone.

`+uri-reserved+` is a string containing the characters reserved in URIs: Colon,
slash, question mark, hash, square brackets, commercial at, exclamation mark,
dollar sign, ampersand, apostrophe (well, ASCII’s approximation thereto,
anyway), parenthesis, asterisk, plus, comma, semicolon, and the equals sign.
