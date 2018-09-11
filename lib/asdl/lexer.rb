require 'lex'

module ASDL

  class Lexer < Lex::Lexer
    tokens(
      :EQUALS,
      :COMMA,
      :QUESTION,
      :PIPE,
      :LPAREN,
      :RPAREN,
      :ASTERISK,
      :LBRACE,
      :RBRACE,
      :TYPEID,
      :CONSTRUCTID,
      :COMMENT
    )


    # Regular expression rules for simple tokens
    rule(:CONSTRUCTID, /[[:upper:]][[:alnum:]_]*/)
    rule(:TYPEID, /[[:lower:]][[:alnum:]_]*/)
    rule(:EQUALS, /=/)
    rule(:COMMA, /,/)
    rule(:QUESTION, /\?/)
    rule(:PIPE, /\|/)
    rule(:LPAREN, /\(/)
    rule(:RPAREN, /\)/)
    rule(:ASTERISK, /\*/)
    rule(:LBRACE, /{/)
    rule(:RBRACE, /}/)


    rule(:COMMENT, /^--.*/) do |lexer,token|

    end





    # Define a rule so we can track line numbers
    rule(:newline, /\n+/) do |lexer, token|
      lexer.advance_line(token.value.length)
    end

    # A string containing ignored characters (spaces and tabs)
    ignore " \t"


    error do |lexer, token|
      puts "Illegal character: #{value}"
    end
  end

end

if $0 == __FILE__
  require 'pry'
  lexer = Lexer.new
  output = lexer.lex ARGF.read
  t = nil
  #binding.pry
  loop do

    t = output.next
    binding.pry if t.line == 69
    puts t
    # binding.pry

  end

end
