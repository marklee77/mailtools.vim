MailTools
=========

This package provides a number of useful functions and settings for editing 
email in mutt. The recommended install procedure is to clone the repository to 
your pathogen bundle folder.

Email Formatter
---------------

This function was developed primarily to provide proper line breaking when
editing email headers in mutt. Lines are broken only after a "," in address
fields, and lines wrap with an indented space as specified by the standard. An
additional feature is that wrapping either with "gqip" or "gq" on a highlighted 
area will respect boundaries between the header, normal body text, different 
quotation levels, and signature. Also, quotations are normalized to use a 
sequence of ">" characters, followed by a single space to promote readability, 
and space indentations are rounded down to the next lowest multiple of 4.

To enable, make sure that the filetype plugin is enabled and put the following
in your .vimrc:

    autocmd FileType mail set formatexpr=FormatEmailText()
