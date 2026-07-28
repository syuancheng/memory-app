import CardForm from "@/components/CardForm";

export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <CardForm mode="edit" cardID={id} />;
}
