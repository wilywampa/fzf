#!/usr/bin/env ruby
# encoding: utf-8

require 'minitest/autorun'

class NilClass
  def include? str
    false
  end
end

module Temp
  def readonce
    name = self.class::TEMPNAME
    waited = 0
    while waited < 5
      begin
        data = File.read(name)
        return data unless data.empty?
      rescue
        sleep 0.1
        waited += 0.1
      end
    end
    raise "failed to read tempfile"
  ensure
    while File.exists? name
      File.unlink name rescue nil
    end
  end
end

class Tmux
  include Temp

  TEMPNAME = '/tmp/fzf-test.txt'

  attr_reader :win

  def initialize shell = 'bash'
    @win = go("new-window -d -P -F '#I' 'PS1=FIN PROMPT_COMMAND= bash --rcfile ~/.fzf.#{shell}'").first
    @lines = `tput lines`.chomp.to_i
  end

  def closed?
    !go("list-window -F '#I'").include?(win)
  end

  def close timeout = 1
    send_keys 'C-c', 'C-u', 'exit', :Enter
    wait(timeout) { closed? }
  end

  def kill
    go("kill-window -t #{win} 2> /dev/null")
  end

  def send_keys *args
    args = args.map { |a| %{"#{a}"} }.join ' '
    go("send-keys -t #{win} #{args}")
  end

  def capture
    go("capture-pane -t #{win} \\; save-buffer #{TEMPNAME}")
    raise "Window not found" if $?.exitstatus != 0
    readonce.split($/)[0, @lines].reverse.drop_while(&:empty?).reverse
  end

  def until timeout = 1
    wait(timeout) { yield capture }
  end

private
  def wait timeout = 1
    waited = 0
    until yield
      waited += 0.1
      sleep 0.1
      if waited > timeout
        hl = '=' * 10
        puts hl
        capture.each_with_index do |line, idx|
          puts [idx.to_s.rjust(2), line].join(': ')
        end
        puts hl
        raise "timeout"
      end
    end
  end

  def go *args
    %x[tmux #{args.join ' '}].split($/)
  end
end

class TestGoFZF < MiniTest::Unit::TestCase
  include Temp

  TEMPNAME = '/tmp/output'

  attr_reader :tmux

  def setup
    ENV.delete 'FZF_DEFAULT_OPTS'
    ENV.delete 'FZF_DEFAULT_COMMAND'
    @tmux = Tmux.new
  end

  def teardown
    @tmux.kill
  end

  def test_vanilla
    tmux.send_keys "seq 1 100000 | fzf > #{TEMPNAME}", :Enter
    tmux.until(10) { |lines| lines.last =~ /^>/ && lines[-2] =~ /^  100000/ }
    lines = tmux.capture
    assert_equal '  2',             lines[-4]
    assert_equal '> 1',             lines[-3]
    assert_equal '  100000/100000', lines[-2]
    assert_equal '>',               lines[-1]

    # Testing basic key bindings
    tmux.send_keys '99', 'C-a', '1', 'C-f', '3', 'C-b', 'C-h', 'C-u', 'C-e', 'C-y', 'C-k', 'Tab', 'BTab'
    tmux.until { |lines| lines[-2] == '  856/100000' }
    lines = tmux.capture
    assert_equal '> 1391',       lines[-4]
    assert_equal '  391',        lines[-3]
    assert_equal '  856/100000', lines[-2]
    assert_equal '> 391',        lines[-1]

    tmux.send_keys :Enter
    tmux.close
    assert_equal '1391', readonce.chomp
  end

  def test_fzf_default_command
    tmux.send_keys "FZF_DEFAULT_COMMAND='echo hello' fzf > #{TEMPNAME}", :Enter
    tmux.until { |lines| lines.last =~ /^>/ }

    tmux.send_keys :Enter
    tmux.close
    assert_equal 'hello', readonce.chomp
  end

  def test_key_bindings
    tmux.send_keys "fzf -q 'foo bar foo-bar'", :Enter
    tmux.until { |lines| lines.last =~ /^>/ }

    # CTRL-A
    tmux.send_keys "C-A", "("
    tmux.until { |lines| lines.last == '> (foo bar foo-bar' }

    # META-F
    tmux.send_keys :Escape, :f, ")"
    tmux.until { |lines| lines.last == '> (foo) bar foo-bar' }

    # CTRL-B
    tmux.send_keys "C-B", "var"
    tmux.until { |lines| lines.last == '> (foovar) bar foo-bar' }

    # Left, CTRL-D
    tmux.send_keys :Left, :Left, "C-D"
    tmux.until { |lines| lines.last == '> (foovr) bar foo-bar' }

    # META-BS
    tmux.send_keys :Escape, :BSpace
    tmux.until { |lines| lines.last == '> (r) bar foo-bar' }

    # CTRL-Y
    tmux.send_keys "C-Y", "C-Y"
    tmux.until { |lines| lines.last == '> (foovfoovr) bar foo-bar' }

    # META-B
    tmux.send_keys :Escape, :b, :Space, :Space
    tmux.until { |lines| lines.last == '> (  foovfoovr) bar foo-bar' }

    # CTRL-F / Right
    tmux.send_keys 'C-F', :Right, '/'
    tmux.until { |lines| lines.last == '> (  fo/ovfoovr) bar foo-bar' }

    # CTRL-H / BS
    tmux.send_keys 'C-H', :BSpace
    tmux.until { |lines| lines.last == '> (  fovfoovr) bar foo-bar' }

    # CTRL-E
    tmux.send_keys "C-E", 'baz'
    tmux.until { |lines| lines.last == '> (  fovfoovr) bar foo-barbaz' }

    # CTRL-U
    tmux.send_keys "C-U"
    tmux.until { |lines| lines.last == '>' }

    # CTRL-Y
    tmux.send_keys "C-Y"
    tmux.until { |lines| lines.last == '> (  fovfoovr) bar foo-barbaz' }

    # CTRL-W
    tmux.send_keys "C-W", "bar-foo"
    tmux.until { |lines| lines.last == '> (  fovfoovr) bar bar-foo' }

    # META-D
    tmux.send_keys :Escape, :b, :Escape, :b, :Escape, :d, "C-A", "C-Y"
    tmux.until { |lines| lines.last == '> bar(  fovfoovr) bar -foo' }

    # CTRL-M
    tmux.send_keys "C-M"
    tmux.until { |lines| lines.last !~ /^>/ }
    tmux.close
  end

  def test_multi_order
    tmux.send_keys "seq 1 10 | fzf --multi > #{TEMPNAME}", :Enter
    tmux.until { |lines| lines.last =~ /^>/ }

    tmux.send_keys :Tab, :Up, :Up, :Tab, :Tab, :Tab, # 3, 2
                   'C-K', 'C-K', 'C-K', 'C-K', :BTab, :BTab, # 5, 6
                   :PgUp, 'C-J', :Down, :Tab, :Tab # 8, 7
    tmux.until { |lines| lines[-2].include? '(6)' }
    tmux.send_keys "C-M"
    tmux.until { |lines| lines[-1].include?('FIN') }
    assert_equal %w[3 2 5 6 8 7], readonce.split($/)
    tmux.close
  end

  def test_with_nth
    [true, false].each do |multi|
      tmux.send_keys "(echo '  1st 2nd 3rd/';
                       echo '  first second third/') |
                      fzf #{"--multi" if multi} -x --nth 2 --with-nth 2,-1,1 > #{TEMPNAME}",
                      :Enter
      tmux.until { |lines| lines[-2].include?('2/2') }

      # Transformed list
      lines = tmux.capture
      assert_equal '  second third/first', lines[-4]
      assert_equal '> 2nd 3rd/1st',        lines[-3]

      # However, the output must not be transformed
      if multi
        tmux.send_keys :BTab, :BTab, :Enter
        tmux.until { |lines| lines[-1].include?('FIN') }
        assert_equal ['  1st 2nd 3rd/', '  first second third/'], readonce.split($/)
      else
        tmux.send_keys '^', '3'
        tmux.until { |lines| lines[-2].include?('1/2') }
        tmux.send_keys :Enter
        tmux.until { |lines| lines[-1].include?('FIN') }
        assert_equal ['  1st 2nd 3rd/'], readonce.split($/)
      end
    end
  end

  def test_scroll
    [true, false].each do |rev|
      tmux.send_keys "seq 1 100 | fzf #{'--reverse' if rev} > #{TEMPNAME}", :Enter
      tmux.until { |lines| lines.include? '  100/100' }
      tmux.send_keys *110.times.map { rev ? :Down : :Up }
      tmux.until { |lines| lines.include? '> 100' }
      tmux.send_keys :Enter
      tmux.until { |lines| lines[-1].include?('FIN') }
      assert_equal '100', readonce.chomp
    end
  end

  def test_select_1
    tmux.send_keys "seq 1 100 | fzf --with-nth ..,.. --print-query -q 5555 -1 > #{TEMPNAME}", :Enter
    tmux.until { |lines| lines[-1].include?('FIN') }
    assert_equal ['5555', '55'], readonce.split($/)
  end

  def test_exit_0
    tmux.send_keys "seq 1 100 | fzf --with-nth ..,.. --print-query -q 555555 -0 > #{TEMPNAME}", :Enter
    tmux.until { |lines| lines[-1].include?('FIN') }
    assert_equal ['555555'], readonce.split($/)
  end

  def test_query_unicode
    tmux.send_keys "(echo abc; echo 가나다) | fzf --query 가다 > #{TEMPNAME}", :Enter
    tmux.until { |lines| lines.last.start_with? '>' }
    tmux.send_keys :Enter
    tmux.until { |lines| lines[-1].include?('FIN') }
    assert_equal ['가나다'], readonce.split($/)
  end
end

