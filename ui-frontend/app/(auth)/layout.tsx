export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="bg-gray-100 flex justify-center items-center min-h-screen w-full">
      {children}
    </div>
  )
}
