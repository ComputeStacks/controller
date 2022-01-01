class Array

  # Average contents of array
  #
  # source: https://github.com/rails-camp/ruby-coding-exercises/blob/solutions/january/14.rb
  #
  def average
    return nil if size.zero?
    inject(&:+) / size
  end
end
