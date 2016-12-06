require 'rexml/document'

class Score
  attr_reader :parts
  def initialize
    @parts = []
  end

  def self.from_file_path(path)
    doc = REXML::Document.new(open(File.expand_path(path)))
    from_document(doc)
  end

  def self.from_document(doc)
    score = Score.new
    doc.elements.each('score-partwise/part') do |e|
      # part - パート
      part = Part.new
      first_part = score.parts.first
      e.elements.each_with_index('measure') do |m, i|
        # measure - 小節
        first = first_part ? first_part.measures[i] : nil
        previous = part.measures.last
        measure = Measure.new(first, previous, m)
        part.measures.push(measure)
      end
      score.parts.push(part)
    end
    score
  end
end

class Part
  attr_reader :measures
  def initialize
    @measures = []
  end
end

class Measure
  attr_reader :bpm, :divisions, :beats, :beat_type, :steps, :step_dur, :bar_dur
  attr_reader :notes_table

  def initialize(first, previous, element)
    @notes_table = {}

    if first
      # 最初のパートの同じ小節のプロパティを引き継ぐ
      @bpm = first.bpm
      @divisions = first.divisions
      @beats = first.beats
      @beat_type = first.beat_type
      @steps = first.steps
      @step_dur = first.step_dur
      @bar_dur = first.bar_dur
    elsif previous
      # 同じパートの直前の小節のプロパティを引き継ぐ
      @bpm = previous.bpm
      @divisions = previous.divisions
      @beats = previous.beats
      @beat_type = previous.beat_type
      @steps = previous.steps
      @step_dur = previous.step_dur
      @bar_dur = previous.bar_dur
    else
      # default values
      @bpm = 120
      @divisions = 1
      @beats = 4
      @beat_type = 4
      @steps = 4
      @step_dur = 0.5
      @bar_dur = 2
    end

    parse(element)
  end

  def parse(element)
    bpm = Measure.extract_bpm(element)
    @bpm = bpm if bpm
    # puts "bpm: #{@bpm}"

    attrs = element.elements['attributes']
    if attrs
      # puts attrs
      divisions = attrs.elements['divisions']
      @divisions = divisions.text.to_f if divisions && divisions.text

      beats = attrs.elements['time/beats']
      @beats = beats.text.to_f if beats && beats.text

      beat_type = attrs.elements['time/beat-type']
      @beat_type = beat_type.text.to_f if beat_type && beat_type.text
    end

    @bar_dur = (60.0 / @bpm) * (4.0 / @beat_type) * @beats
    # puts "bar_dur: #{@bar_dur}"

    @step_dur = (60.0 / @bpm) * (4.0 / @beat_type) / @divisions
    # puts "step_dur: #{@step_dur}"

    @steps = (@beats * @divisions).to_i
    # puts "steps: #{@steps}"

    current_step = 0
    note = nil
    element.elements.each do |nb|
      # puts nb
      if nb.name == 'note'
        is_chord = nb.elements['chord']
        rest = nb.elements['rest']
        pitch_step = nb.elements['pitch/step']
        pitch_alter = nb.elements['pitch/alter']
        pitch_octave = nb.elements['pitch/octave']
        duration = nb.elements['duration']
        next if !duration || !duration.text

        note_sym = ''
        if pitch_step && pitch_step.text && pitch_octave && pitch_octave.text
          alter = pitch_alter.text == '1' ? 's' : 'b' if pitch_alter && pitch_alter.text
          note_sym = "#{pitch_step.text}#{alter}#{pitch_octave.text}".intern
          if is_chord
            # コードの場合、直前のnoteに追加するだけ
            note.notes.push(note_sym)
            next
          end
        elsif rest
          note_sym = 'r'.intern
        end

        note = Note.new
        note.notes.push(note_sym)

        time = @step_dur * duration.text.to_i
        note.duration = time
        add_to_notes_table(current_step, note)

        current_step += duration.text.to_i
      elsif nb.name == 'backup'
        duration = nb.elements['duration']
        next if !duration || !duration.text
        current_step -= duration.text.to_i
        current_step = 0 if current_step < 0
      end
    end

    # puts @notes_table
  end

  def add_to_notes_table(key, value)
    @notes_table[key] = [] unless @notes_table[key]
    @notes_table[key].push(value)
  end

  def self.extract_bpm(measure)
    per_minute = measure.elements['direction/direction-type/metronome/per-minute']
    return per_minute.text.to_f if per_minute && per_minute.text

    sound = measure.elements['direction/sound']
    return sound.attributes['tempo'].to_f if sound && sound.attributes['tempo']

    nil
  end
end

class Note
  attr_reader :notes
  attr_accessor :duration
  def initialize
    @notes = []
    @duration = 1
  end

  def to_s
    "@notes: #{@notes}, @duration: #{@duration}"
  end
end

def play_musicxml(file_path)
  start_time = Time.now.to_f
  score = Score.from_file_path(file_path)
  end_time = Time.now.to_f
  parsing_time = end_time - start_time
  puts "parsing_time: #{parsing_time}"
  set_sched_ahead_time!(parsing_time * 1.2)

  score.parts.each do |part|
    in_thread do
      part.measures.each do |measure|
        measure.steps.times do |step|
          notes = measure.notes_table[step]
          if notes
            notes.each do |n|
              # #| puts n.notes
              # #| puts n.duration
              in_thread do
                play n.notes, release: n.duration
              end
            end
          end
          sleep measure.step_dur
        end
      end
    end
  end
end

# play_musicxml('~/sonic-pi-musicxml-player/harunoumi_v2.xml')
# play_musicxml('~/sonic-pi-musicxml-player/lg-203466147999847691.xml')
# play_musicxml('~/sonic-pi-musicxml-player/lg-541051287770799445.xml')
play_musicxml('~/sonic-pi-musicxml-player/lg-641011115129979680.xml')
# play_musicxml('~/sonic-pi-musicxml-player/sakura.xml')
