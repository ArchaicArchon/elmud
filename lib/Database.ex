require Amnesia
use Amnesia

defdatabase Database do
  deftable Item, [:key, :value], type: :ordered_set do
    @type t :: %Item{key: String.t, value: String.t}
  end
end

