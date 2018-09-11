require 'pp'

class Reflow

  attr_reader :tabsize, :max_col



  def initialize(tabsize: 4, max_col: 80)
    @tabsize = tabsize
    @max_col = 80
  end


  def reflow_lines(s,depth)


    size = max_col - (depth * tabsize)
    return [s] if s.size < size

    lines = []
    cur = s
    padding = String.new
    while cur.size > size
      i = cur.rindex(' ', size)
      lines.append(padding + cur[0..i])
      if lines.size == 1
        j = cur.index('{')
        if j and j >= 0
          j += 2 # account for the brace and space after it
          size -= j
          padding = " " * j
        else
          j = cur[0..i].index('(')
          if j and j>= 0
            j += 1 # account for paren (no space after it)
            size -= j
            padding = " " * j
          end
        end
      end
      cur = cur[i+1..-1]
    end
    lines.append(padding + cur)
    return lines
  end

end
