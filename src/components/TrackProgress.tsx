const handleSaveProgress = async () => {
  setSaving(true);
  try {
    // ... your lesson update logic ...
    // Refetch contract and lessons after update
    await fetchContractData();
    toast.success('Fortschritt gespeichert');
  } catch (error) {
    toast.error('Fehler beim Speichern des Fortschritts');
  } finally {
    setSaving(false);
  }
}; 