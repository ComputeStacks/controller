class String

  ##
  # Allow only alpha numeric characters (A-Za-z0-9),
  # and removing any whitespace
  def to_alpha
    gsub(/[^\p{Alnum}\p{Space}-]/, '').squish.gsub(/\s+/, '')
  end

  ##
  # Clean string for querying a database
  # Should be mostly the same result as to_alpha, except:
  # * we allow @ for email addresses
  # * allow '.'
  def allowed_query
    delete('=').delete('!').delete('\\')
               .delete('"').delete("'").delete('&')
               .delete('%').delete('~').delete('{')
               .delete('}').delete('(').delete(')')
               .delete('$').delete('`').delete('|')
               .delete(';').delete('>').delete('<')
               .delete('*').delete('[').delete(']').squish
  end

end
