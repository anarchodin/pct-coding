;;;; This file includes a set of functions which enable percent-encoding of
;;;; _arbitrary_ binary data. In the current incarnation it relies on Babel to
;;;; perform the lowest-level transform; this may be reconsidered later. The
;;;; encoding function, in particular, feels icky.

;;;; If distributed separately, consider this file under the CC0 licence -
;;;; effectively public domain. (I happen to live in a country which does not
;;;; enable authors to disclaim all copyright, so something likely to stand up
;;;; to scrutiny seems a good bet.)

;;;; ASSUMES CHARACTER CODES ARE ASCII COMPATIBLE

(defpackage #:pct-coding
  (:use #:cl)
  (:export #:+uri-reserved+
           #:pct-encode
           #:pct-decode
           #:pct-normalize))

(in-package #:pct-coding)

(defun hex-digit-p (char-or-code)
  (check-type char-or-code (or character (unsigned-byte 8)))
  (let ((c (typecase char-or-code
             (character (char-code char-or-code))
             ((unsigned-byte 8) char-or-code))))
    (or (<= #x30 c #x39)
        (<= #x41 c #x46)
        (<= #x61 c #x66))))

(defun uri-char-p (char-or-code)
  "Can the given character (or character code) validly appear directly in an
URI?"
  (check-type char-or-code (or character (unsigned-byte 8)))
  (let ((c (typecase char-or-code
             (character (char-code char-or-code))
             ((unsigned-byte 8) char-or-code))))
    (or (= c #x21)
        (<= #x23 c #x3B)
        (= c #x3D)
        (<= #x3F c #x5B)
        (= c #x5D)
        (= c #x5F)
        (<= #x61 c #x7A)
        (= c #x7E))))

(defconstant +uri-reserved+ ":/?#[]@!$&'()*+,;="
  "A sequence containing the characters reserved in RFC3986. It is used as the
default set of reserved characters in percent-encoding.")

(defun reservedp (char-or-code &key (reserved +uri-reserved+))
  (check-type char-or-code (or character (unsigned-byte 8)))
  (let ((c (typecase char-or-code
             (character char-or-code)
             ((unsigned-byte 8) (code-char char-or-code)))))
    (find c reserved)))

(defun pct-encode (octet-vector &key (iri t) (reserved +uri-reserved+) (ignore-existing nil))
  "Takes a vector of octets and returns the corresponding percent-encoded string.

By default, attempts to transform UTF-8 sequences into the corresponding
codepoints. Passing nil to the keyword argument :iri suppresses it.

By default, replaces reserved characters with their percent-encoded
form. Reserved characters are passed as a sequence with the :reserved keyword,
defaulting to the reserved characters of URIs.

By default, will encode every occurence of the percent sign (octet with value
#x25). If :ignore-existing is given a non-nil value, will pass byte sequences
corresponding to percent-encoded octets through to the result string without
encoding the percent-sign. This transform exists to enable normalisation of
already-encoded strings."
  (check-type octet-vector (vector (unsigned-byte 8)))
  (with-output-to-string (encoded)
    (do ((vector-length (length octet-vector))
         (i 0 (1+ i)))
        ((>= i vector-length))
      (let ((octet (aref octet-vector i)))
        (cond
          ((and (= #x25 octet) ignore-existing ; It's a percent sign...
                (>= vector-length (+ i 3)) ; ... and I think it may be encoding something...
                (let ((first (aref octet-vector (+ i 1)))
                      (second (aref octet-vector (+ i 2))))
                  (and (hex-digit-p first)
                       (hex-digit-p second)))) ; ... IT IS, IT IS ENCODING SOMETHING!
           (write-string
            (format nil "%~2,'0x"
                    (parse-integer (babel:octets-to-string octet-vector
                                                           :start (+ i 1)
                                                           :end (+ i 3)
                                                           :encoding :utf-8)
                                   :radix 16))
            encoded)
           (incf i 2))
          ((and (uri-char-p octet)
                (not (reservedp octet :reserved reserved))
                (not (= octet #x25))) ; Don't write out a percent-sign that's not encoding something.
           (write-char (code-char octet) encoded))
          ((and iri
                (<= #xC2 octet #xDF) (>= vector-length (+ i 2)) ; Two bytes...
                (<= #x80 (aref octet-vector (+ i 1)) #xBF)) ; ... and both of them actual continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 2) :encoding :utf-8) encoded)
           (incf i))
          ((and iri
                (= #xE0 octet) (>= vector-length (+ i 3)) ; Three bytes...
                (<= #xA0 (aref octet-vector (+ i 1)) #xBF) ; ... not overlong...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF)) ; ... and two continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8) encoded)
           (incf i 2))
          ((and iri
                (<= #xE1 octet #xEC) (>= vector-length (+ i 3)) ; Three bytes...
                (<= #x80 (aref octet-vector (+ i 1)) #xBF) ; ... one continuation byte...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF)) ; ... and two continuation bytes.
           (let* ((string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8))
                  (code (char-code (char string 0))))
             (if (or (<= #x202A code #x202E) ; Bidirectional controls.
                     (<= #x2066 code #x2069)) ; Not a good idea in IRIs.
                 (format encoded "%~2,'0x" octet) ; Treat as non-URI characters.
                 (progn (write-string string encoded)
                        (incf i 2)))))
          ((and iri
                (= #xED octet) (>= vector-length (+ i 3)) ; Three bytes...
                (<= #x80 (aref octet-vector (+ i 1)) #x9F) ; ... not overlong...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF)) ; ... and two continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8) encoded)
           (incf i 2))
          ((and iri
                (<= #xEE octet #xEF) (>= vector-length (+ i 3)) ; Three bytes...
                (<= #x80 (aref octet-vector (+ i 1)) #xBF) ; ... one continuation byte...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF)) ; ... and two continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8) encoded)
           (incf i 2))
          ((and iri
                (= #xF0 octet) (>= vector-length (+ i 4)) ; Four bytes...
                (<= #x90 (aref octet-vector (+ i 1)) #xBF) ; ... not overlong...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF) ; ... and two continuation bytes...
                (<= #x80 (aref octet-vector (+ i 3)) #xBF)) ; ... and three continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8) encoded)
           (incf i 3))
          ((and iri
                (<= #xF1 octet #xF3) (>= vector-length (+ i 4)) ; Four bytes...
                (<= #x80 (aref octet-vector (+ i 1)) #xBF) ; ... and one continuation byte...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF) ; ... and two continuation bytes...
                (<= #x80 (aref octet-vector (+ i 3)) #xBF)) ; ... and three continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8) encoded)
           (incf i 3))
          ((and iri
                (= #xF4 octet) (>= vector-length (+ i 4)) ; Four bytes...
                (<= #x80 (aref octet-vector (+ i 1)) #x8F) ; ... not overlong...
                (<= #x80 (aref octet-vector (+ i 2)) #xBF) ; ... and two continuation bytes...
                (<= #x80 (aref octet-vector (+ i 3)) #xBF)) ; ... and three continuation bytes.
           (write-string (babel:octets-to-string octet-vector :start i :end (+ i 3) :encoding :utf-8) encoded)
           (incf i 3))
          (t (write-string (format nil "%~2,'0x" octet) encoded)))))))

(defun pct-decode (string &key (encoding :utf-8) (reserved nil))
  "Takes a percent-encoded string and returns the octets it represents as a vector.

By default, transforms characters not allowed in URIs into their UTF-8 octet
representations. An alternative encoding can be specified using the :encoding
keyword argument.

By default, transforms all percent-encoded sequences in the source string into
their corresponding octets. The behaviour can be changed by passing a sequence
of characters using the :reserved keyword argument. Percent-encodings
corresponding to characters found in the sequence will be translated as if the
percent-sign was itself escaped. As this transform is performed byte-wise, it
can only ever impact characters in ASCII, and which are permitted to appear
directly in URIs. It exists to enable normalisation of already-encoded strings."
  (check-type string string)
  (let ((buffer (make-array 10 :element-type '(unsigned-byte 8) :adjustable t :fill-pointer 0)))
    (do ((i 0 (1+ i)))
        ((>= i (length string)) buffer)
      (let* ((x (char string i)))
        (cond
          ((and (char= #\% x)
                (>= (length string) (+ i 3))) ; long enough for escaped octet?
           (let ((escaped (subseq string (+ i 1) (+ i 3))))
             (if (every #'hex-digit-p escaped)
                 (let ((encoded (parse-integer escaped :radix 16)))
                   (if (reservedp encoded :reserved reserved) ; is it in the reserved set?
                       (vector-push-extend #x25 buffer) ; then forget it
                       (progn (vector-push-extend (parse-integer escaped :radix 16) buffer)
                              (incf i 2)))) ; ^ else decode octet and push on
                 (vector-push-extend #x25 buffer)))) ; if it's not followed by hex
          ((and (uri-char-p x)
                (not (reservedp x :reserved reserved)))
           (vector-push-extend (char-code x) buffer))
          (t (map nil #'(lambda (x) (vector-push-extend x buffer))
                  (babel:string-to-octets (string x) :encoding encoding))))))))

(defun pct-normalize (string &key (iri t) (encoding :utf-8) (reserved +uri-reserved+))
  "Takes a string and returns a normalised, percent-encoded string that
represents the same binary data. This means that it will decode any unreserved
characters in the string, encode any characters not permitted to appear
directly, and pass reserved characters through in the same form, whether encoded
or not. All percent-encodings in the final string will use uppercase
letters. Works with IRIs by default.

The set of reserved characters can be altered by passing a sequence of
characters to :reserved; it will only work for ASCII characters allowed in
URIs. The encoding used to transform percent-encodings in the input string can
be configured using the :encoding parameter."
  (check-type string string)
  (pct-encode (pct-decode string :encoding encoding :reserved reserved)
              :iri iri :reserved nil :ignore-existing t))
